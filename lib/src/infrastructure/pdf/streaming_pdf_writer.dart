import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../config/pdf_config.dart';

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

  /// Streams a single image page into the PDF document.
  ///
  /// [encodedStream] must be either raw JPEG bytes (`filter: '/DCTDecode'`) or
  /// zlib-compressed raw pixel bytes (`filter: '/FlateDecode'`).
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

    final imgId = _allocateId();
    final contentId = _allocateId();
    final pageId = _allocateId();

    // 1. Image XObject stream.
    _beginObject(imgId);
    _writeAscii(
      '<< /Type /XObject /Subtype /Image '
      '/Width $imageWidth /Height $imageHeight '
      '/ColorSpace $colorSpace /BitsPerComponent 8 '
      '/Filter $filter /Length ${encodedStream.length} >>\nstream\n',
    );
    _writeRaw(encodedStream);
    _writeAscii('\nendstream');
    _endObject();

    // 2. Page content stream placing /Im0 with exact affine matrix.
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

    // 3. Page dictionary.
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

  /// Writes `/Catalog`, `/Pages`, `/Info`, `xref`, and `trailer`, then closes
  /// the underlying file handle and returns total bytes written.
  int finish(PdfDocumentMetadata metadata, DateTime createdAt) {
    try {
      // Object 1: Document Catalog.
      _beginObject(1);
      _writeAscii('<< /Type /Catalog /Pages 2 0 R >>');
      _endObject();

      // Object 2: Pages tree root.
      final kids = _pageObjectIds.map((id) => '$id 0 R').join(' ');
      _beginObject(2);
      _writeAscii(
        '<< /Type /Pages /Kids [$kids] /Count ${_pageObjectIds.length} >>',
      );
      _endObject();

      // Object 3: Document Info dictionary.
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

      // Cross-reference table (strict 20-byte entries).
      final xrefOffset = _bytePosition;
      final totalObjects = _nextObjectId;
      _writeAscii('xref\n0 $totalObjects\n');
      _writeAscii('0000000000 65535 f \r\n');
      for (var id = 1; id < totalObjects; id++) {
        final offset = _offsets[id] ?? 0;
        _writeAscii('${offset.toString().padLeft(10, '0')} 00000 n \r\n');
      }

      // Trailer & EOF.
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
    // UTF-16BE BOM hex string for full Unicode (e.g. Bangla, Arabic, CJK) metadata!
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
    return "D:${u.year.toString().padLeft(4, '0')}"
        "${p2(u.month)}${p2(u.day)}${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z";
  }
}
