import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../config/nid_scan_config.dart';
import '../../config/pdf_config.dart';

/// Encoded PDF XObject payload for one image placed on a PDF page.
typedef PdfEncodedImage = ({
  Uint8List encodedStream,
  int imageWidth,
  int imageHeight,
  String colorSpace,
  String filter,
  int extraQuarterTurns,
});

/// Low-level streaming PDF 1.4 writer that writes objects directly to a
/// [RandomAccessFile] while recording exact byte offsets for the `xref` table.
///
/// Memory usage remains O(1) per page regardless of total page count.
class StreamingPdfWriter {
  /// Opens [file] for synchronous streaming PDF output.
  StreamingPdfWriter(File file)
    : _raf = file.openSync(mode: FileMode.writeOnly) {
    // PDF 1.4 header + 4 high-bit binary comment bytes per PDF spec §7.5.2.
    _writeRaw(
      Uint8List.fromList([
        ...ascii.encode('%PDF-1.4\n%'),
        0xE2,
        0xE3,
        0xCF,
        0xD3,
        0x0A,
      ]),
    );
  }

  final RandomAccessFile _raf;
  final Map<int, int> _offsets = <int, int>{};
  final List<int> _pageObjectIds = <int>[];
  int _bytePosition = 0;

  // Reserved object IDs: 1 = Catalog, 2 = Pages, 3 = Info.
  int _nextObjectId = 4;

  int _allocateId() => _nextObjectId++;

  void _writeRaw(List<int> bytes) {
    _raf.writeFromSync(bytes);
    _bytePosition += bytes.length;
  }

  void _writeAscii(String text) => _writeRaw(latin1.encode(text));

  void _beginObject(int id) {
    _offsets[id] = _bytePosition;
    _writeAscii('$id 0 obj\n');
  }

  void _endObject() {
    _writeAscii('\nendobj\n');
  }

  int _writeImageXObject(PdfEncodedImage img) {
    final imgId = _allocateId();
    _beginObject(imgId);
    _writeAscii(
      '<< /Type /XObject /Subtype /Image '
      '/Width ${img.imageWidth} /Height ${img.imageHeight} '
      '/ColorSpace ${img.colorSpace} /BitsPerComponent 8 '
      '/Filter ${img.filter} /Length ${img.encodedStream.length} >>\nstream\n',
    );
    _writeRaw(img.encodedStream);
    _writeAscii('\nendstream');
    _endObject();
    return imgId;
  }

  /// Streams a single image page into the PDF document.
  void addImagePage({
    required Uint8List encodedStream,
    required int imageWidth,
    required int imageHeight,
    required String colorSpace,
    required String filter,
    required PdfConfig config,
    int extraQuarterTurns = 0,
  }) {
    final turns = ((extraQuarterTurns % 4) + 4) % 4;
    final swapped = turns.isOdd;
    final dispW = (swapped ? imageHeight : imageWidth).toDouble();
    final dispH = (swapped ? imageWidth : imageHeight).toDouble();

    final (pageW, pageH) = _resolvePageBox(dispW, dispH, config);
    final margins = config.marginsPt;
    final boxX = margins.left.clamp(0.0, pageW);
    final boxY = margins.bottom.clamp(0.0, pageH);
    final availW = math.max(1.0, pageW - margins.left - margins.right);
    final availH = math.max(1.0, pageH - margins.top - margins.bottom);

    final (drawX, drawY, drawW, drawH, clipToBox) = _resolvePlacement(
      dispW: dispW,
      dispH: dispH,
      boxX: boxX,
      boxY: boxY,
      availW: availW,
      availH: availH,
      fit: config.imageFit,
    );

    final imgId = _writeImageXObject((
      encodedStream: encodedStream,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      colorSpace: colorSpace,
      filter: filter,
      extraQuarterTurns: turns,
    ));
    final contentId = _allocateId();
    final pageId = _allocateId();

    final matrixCmd = _buildMatrixCommand(
      turns: turns,
      x: drawX,
      y: drawY,
      w: drawW,
      h: drawH,
    );
    final clipCmd = clipToBox
        ? '${_fmt(boxX)} ${_fmt(boxY)} ${_fmt(availW)} ${_fmt(availH)} re W n\n'
        : '';
    final contentBytes = ascii.encode('q\n$clipCmd$matrixCmd\n/Im0 Do\nQ\n');

    _beginObject(contentId);
    _writeAscii('<< /Length ${contentBytes.length} >>\nstream\n');
    _writeRaw(contentBytes);
    _writeAscii('\nendstream');
    _endObject();

    _beginObject(pageId);
    _writeAscii(
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 ${_fmt(pageW)} ${_fmt(pageH)}] '
      '/Resources << /ProcSet [/PDF /ImageB /ImageC] '
      '/XObject << /Im0 $imgId 0 R >> >> '
      '/Contents $contentId 0 R >>',
    );
    _endObject();

    _pageObjectIds.add(pageId);
  }

  /// Composes one or two NID card images (`front` and optional `back`) onto a
  /// **single** fixed PDF page (e.g. A4) according to [nidConfig] without
  /// re-encoding either image stream.
  void addNidCompositePage({
    required PdfEncodedImage front,
    PdfEncodedImage? back,
    required NidScanConfig nidConfig,
  }) {
    final targetSize = nidConfig.targetPageSize.isFitToImage
        ? PdfPageSize.a4
        : nidConfig.targetPageSize;
    final shortSide = math.min(targetSize.widthPt, targetSize.heightPt);
    final longSide = math.max(targetSize.widthPt, targetSize.heightPt);

    final sideBySide =
        back != null &&
        nidConfig.pdfLayout == NidPdfLayout.sideBySideSinglePage;
    // Top-and-bottom looks best on portrait A4; side-by-side uses portrait when
    // cards fit or landscape if needed, keeping portrait A4 for standard KYC sheets.
    final pageW = shortSide;
    final pageH = longSide;

    final margin = nidConfig.pageMarginsPt.clamp(0.0, pageW * 0.25);
    final gap = nidConfig.gapBetweenCardsPt.clamp(4.0, 120.0);
    final availW = math.max(36.0, pageW - margin * 2);
    final availH = math.max(36.0, pageH - margin * 2);

    (double, double) orientedDims(PdfEncodedImage img) {
      final t = ((img.extraQuarterTurns % 4) + 4) % 4;
      final w = (t.isOdd ? img.imageHeight : img.imageWidth).toDouble();
      final h = (t.isOdd ? img.imageWidth : img.imageHeight).toDouble();
      if (nidConfig.normalizeCardAspectRatio &&
          nidConfig.isoCardAspectRatio > 0) {
        final ratio = w >= h
            ? nidConfig.isoCardAspectRatio
            : 1.0 / nidConfig.isoCardAspectRatio;
        return (1000.0 * ratio, 1000.0);
      }
      return (math.max(1.0, w), math.max(1.0, h));
    }

    (double, double) cardBoxSize(
      (double, double) dims, {
      required double slotMaxW,
      required double slotMaxH,
    }) {
      final aspect = dims.$1 / dims.$2;
      double desiredW;
      switch (nidConfig.cardPrintSize) {
        case NidCardPrintSize.actualIsoId1:
          // ISO/IEC 7810 ID-1: 85.60 mm = 242.65 pt, 53.98 mm = 153.01 pt.
          desiredW = aspect >= 1.0 ? 242.65 : 153.01;
        case NidCardPrintSize.readableMedium:
          desiredW = sideBySide ? slotMaxW * 0.94 : pageW * 0.62;
        case NidCardPrintSize.largeFit:
          desiredW = slotMaxW;
      }
      var w = math.min(desiredW, slotMaxW);
      var h = w / aspect;
      if (h > slotMaxH) {
        h = slotMaxH;
        w = h * aspect;
      }
      return (w, h);
    }

    final frontId = _writeImageXObject(front);
    final backId = back == null ? null : _writeImageXObject(back);

    final commands = StringBuffer();
    final frontDims = orientedDims(front);
    final frontTurns = ((front.extraQuarterTurns % 4) + 4) % 4;

    if (back == null) {
      final (fw, fh) = cardBoxSize(
        frontDims,
        slotMaxW: availW,
        slotMaxH: availH,
      );
      final fx = margin + (availW - fw) / 2;
      // Place single-sided NID cleanly in upper-middle portion of A4.
      final fy = pageH - margin - fh - math.min(48.0, (availH - fh) * 0.25);
      final m0 = _buildMatrixCommand(
        turns: frontTurns,
        x: fx,
        y: fy,
        w: fw,
        h: fh,
      );
      commands.writeln('q\n$m0\n/Im0 Do\nQ');
    } else if (sideBySide) {
      final backDims = orientedDims(back);
      final backTurns = ((back.extraQuarterTurns % 4) + 4) % 4;
      final slotW = math.max(18.0, (availW - gap) / 2);
      final (fw, fh) = cardBoxSize(
        frontDims,
        slotMaxW: slotW,
        slotMaxH: availH,
      );
      final (bw, bh) = cardBoxSize(backDims, slotMaxW: slotW, slotMaxH: availH);

      final groupW = fw + gap + bw;
      final startX = margin + (availW - groupW) / 2;
      final centerY =
          pageH - margin - math.min(availH * 0.35, math.max(fh, bh) + 36);

      final fy = (centerY).clamp(margin, pageH - margin - fh);
      final by = (fy + (fh - bh) / 2).clamp(margin, pageH - margin - bh);

      final m0 = _buildMatrixCommand(
        turns: frontTurns,
        x: startX,
        y: fy,
        w: fw,
        h: fh,
      );
      final m1 = _buildMatrixCommand(
        turns: backTurns,
        x: startX + fw + gap,
        y: by,
        w: bw,
        h: bh,
      );
      commands.writeln('q\n$m0\n/Im0 Do\nQ');
      commands.writeln('q\n$m1\n/Im1 Do\nQ');
    } else {
      // Default: Front on top, Back below, centered horizontally on 1 A4 page!
      final backDims = orientedDims(back);
      final backTurns = ((back.extraQuarterTurns % 4) + 4) % 4;
      final slotH = math.max(18.0, (availH - gap) / 2);
      final (fw, fh) = cardBoxSize(
        frontDims,
        slotMaxW: availW,
        slotMaxH: slotH,
      );
      final (bw, bh) = cardBoxSize(backDims, slotMaxW: availW, slotMaxH: slotH);

      final totalStackH = fh + gap + bh;
      // Center vertically on the sheet.
      final bottomY = margin + (availH - totalStackH) / 2;
      final backY = bottomY;
      final frontY = bottomY + bh + gap;

      final frontX = margin + (availW - fw) / 2;
      final backX = margin + (availW - bw) / 2;

      final m0 = _buildMatrixCommand(
        turns: frontTurns,
        x: frontX,
        y: frontY,
        w: fw,
        h: fh,
      );
      final m1 = _buildMatrixCommand(
        turns: backTurns,
        x: backX,
        y: backY,
        w: bw,
        h: bh,
      );
      commands.writeln('q\n$m0\n/Im0 Do\nQ');
      commands.writeln('q\n$m1\n/Im1 Do\nQ');
    }

    final contentBytes = ascii.encode(commands.toString());
    final contentId = _allocateId();
    final pageId = _allocateId();

    _beginObject(contentId);
    _writeAscii('<< /Length ${contentBytes.length} >>\nstream\n');
    _writeRaw(contentBytes);
    _writeAscii('\nendstream');
    _endObject();

    final xObjects = backId == null
        ? '/Im0 $frontId 0 R'
        : '/Im0 $frontId 0 R /Im1 $backId 0 R';

    _beginObject(pageId);
    _writeAscii(
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 ${_fmt(pageW)} ${_fmt(pageH)}] '
      '/Resources << /ProcSet [/PDF /ImageB /ImageC] '
      '/XObject << $xObjects >> >> '
      '/Contents $contentId 0 R >>',
    );
    _endObject();

    _pageObjectIds.add(pageId);
  }

  /// Writes `/Catalog`, `/Pages`, `/Info`, `xref`, and `trailer`, then closes
  /// the underlying file handle and returns total bytes written.
  int finish(PdfDocumentMetadata metadata, DateTime createdAt) {
    try {
      _beginObject(1);
      _writeAscii('<< /Type /Catalog /Pages 2 0 R >>');
      _endObject();

      final kids = _pageObjectIds.map((id) => '$id 0 R').join(' ');
      _beginObject(2);
      _writeAscii(
        '<< /Type /Pages /Kids [$kids] /Count ${_pageObjectIds.length} >>',
      );
      _endObject();

      _beginObject(3);
      final infoEntries = <String>[
        if (metadata.title != null && metadata.title!.isNotEmpty)
          '/Title ${_pdfString(metadata.title!)}',
        if (metadata.author != null && metadata.author!.isNotEmpty)
          '/Author ${_pdfString(metadata.author!)}',
        if (metadata.subject != null && metadata.subject!.isNotEmpty)
          '/Subject ${_pdfString(metadata.subject!)}',
        if (metadata.keywords != null && metadata.keywords!.isNotEmpty)
          '/Keywords ${_pdfString(metadata.keywords!)}',
        '/Creator ${_pdfString(metadata.creator)}',
        '/Producer ${_pdfString(metadata.producer)}',
        '/CreationDate (${_pdfDate(createdAt)})',
      ];
      _writeAscii('<< ${infoEntries.join(' ')} >>');
      _endObject();

      final xrefOffset = _bytePosition;
      final totalObjects = _nextObjectId;
      _writeAscii('xref\n0 $totalObjects\n');
      _writeAscii('0000000000 65535 f \r\n');
      for (var id = 1; id < totalObjects; id++) {
        final offset = _offsets[id] ?? 0;
        _writeAscii('${offset.toString().padLeft(10, '0')} 00000 n \r\n');
      }

      _writeAscii(
        'trailer\n'
        '<< /Size $totalObjects /Root 1 0 R /Info 3 0 R >>\n'
        'startxref\n'
        '$xrefOffset\n'
        '%%EOF\n',
      );
      _raf.flushSync();
      return _bytePosition;
    } finally {
      _raf.closeSync();
    }
  }

  /// Closes the writer on error without finalizing.
  void abort() {
    try {
      _raf.closeSync();
    } on Object {
      // Already closed.
    }
  }

  static (double, double) _resolvePageBox(
    double dispW,
    double dispH,
    PdfConfig config,
  ) {
    final size = config.pageSize;
    if (size.isFitToImage) {
      final dpi = config.dpi <= 0 ? 150.0 : config.dpi;
      final scale = 72.0 / dpi;
      final w = dispW * scale + config.marginsPt.left + config.marginsPt.right;
      final h = dispH * scale + config.marginsPt.top + config.marginsPt.bottom;
      return (math.max(18.0, w), math.max(18.0, h));
    }

    final shortSide = math.min(size.widthPt, size.heightPt);
    final longSide = math.max(size.widthPt, size.heightPt);
    return switch (config.orientation) {
      PdfPageOrientation.portrait => (shortSide, longSide),
      PdfPageOrientation.landscape => (longSide, shortSide),
      PdfPageOrientation.auto =>
        dispW > dispH ? (longSide, shortSide) : (shortSide, longSide),
    };
  }

  static (double, double, double, double, bool) _resolvePlacement({
    required double dispW,
    required double dispH,
    required double boxX,
    required double boxY,
    required double availW,
    required double availH,
    required PdfImageFit fit,
  }) {
    switch (fit) {
      case PdfImageFit.fill:
        return (boxX, boxY, availW, availH, false);
      case PdfImageFit.contain:
        final s = math.min(availW / dispW, availH / dispH);
        final w = dispW * s;
        final h = dispH * s;
        return (boxX + (availW - w) / 2, boxY + (availH - h) / 2, w, h, false);
      case PdfImageFit.cover:
        final s = math.max(availW / dispW, availH / dispH);
        final w = dispW * s;
        final h = dispH * s;
        return (boxX + (availW - w) / 2, boxY + (availH - h) / 2, w, h, true);
    }
  }

  static String _buildMatrixCommand({
    required int turns,
    required double x,
    required double y,
    required double w,
    required double h,
  }) => switch (turns) {
    0 => '${_fmt(w)} 0 0 ${_fmt(h)} ${_fmt(x)} ${_fmt(y)} cm',
    1 => '0 ${_fmt(-h)} ${_fmt(w)} 0 ${_fmt(x)} ${_fmt(y + h)} cm',
    2 => '${_fmt(-w)} 0 0 ${_fmt(-h)} ${_fmt(x + w)} ${_fmt(y + h)} cm',
    3 => '0 ${_fmt(h)} ${_fmt(-w)} 0 ${_fmt(x + w)} ${_fmt(y)} cm',
    _ => '${_fmt(w)} 0 0 ${_fmt(h)} ${_fmt(x)} ${_fmt(y)} cm',
  };

  static String _fmt(double v) {
    final s = v.toStringAsFixed(3);
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _pdfString(String value) {
    final isAscii = value.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    if (isAscii) {
      final escaped = value
          .replaceAll(r'\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      return '($escaped)';
    }
    final hex = StringBuffer('<FEFF');
    for (final unit in value.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    hex.write('>');
    return hex.toString();
  }

  static String _pdfDate(DateTime dt) {
    final u = dt.toUtc();
    String p2(int n) => n.toString().padLeft(2, '0');
    return 'D:${u.year.toString().padLeft(4, '0')}'
        '${p2(u.month)}${p2(u.day)}${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
  }
}
