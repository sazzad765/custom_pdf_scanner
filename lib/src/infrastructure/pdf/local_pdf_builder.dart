import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path/path.dart' as p;

import '../../config/nid_scan_config.dart';
import '../../config/pdf_config.dart';
import '../../domain/scanned_page.dart';
import '../../domain/scanned_pdf_result.dart';
import '../../domain/scanner_failure.dart';
import '../crop/jpeg_header.dart';
import '../processing/opencv_support.dart';
import 'streaming_pdf_writer.dart';

/// Input item when calling [LocalPdfBuilder.buildFromFiles] directly without
/// a `CustomScannerController`.
class PdfPageInput {
  /// Creates a [PdfPageInput] pointing to a local image file.
  const PdfPageInput({
    required this.imagePath,
    this.extraRotationQuarterTurns = 0,
  });

  /// Local path to a JPEG, PNG, or OpenCV-supported image file.
  final String imagePath;

  /// Optional extra clockwise 90° quarter turns (`0..3`) applied in the PDF layout.
  final int extraRotationQuarterTurns;
}

/// High-efficiency local PDF builder that streams scanned pages directly to disk
/// in a background isolate, supporting both standard multi-page documents and
/// composite single-page Front + Back NID card layouts.
class LocalPdfBuilder {
  /// Creates a [LocalPdfBuilder].
  const LocalPdfBuilder({this.config = const PdfConfig()});

  /// PDF layout, output path, and metadata settings.
  final PdfConfig config;

  /// Builds a local `.pdf` file from ordered [ScannedPage] items.
  ///
  /// When [nidCompositeConfig] is provided (and `pdfLayout != NidPdfLayout.separatePages`),
  /// pairs of NID sides (`Front` and optional `Back`) are composed onto a single
  /// fixed PDF page (`pageCount == 1`).
  Future<ScannedPdfResult> buildFromScannedPages({
    required List<ScannedPage> pages,
    String? outputFilePath,
    PdfConfig? overrideConfig,
    NidScanConfig? nidCompositeConfig,
    void Function(PdfGenerationProgress progress)? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const PdfGenerationException(
        'Cannot generate a PDF with zero pages.',
      );
    }
    final cfg = overrideConfig ?? config;
    final resolvedPath = await _resolveOutputPath(outputFilePath, cfg);
    final inputs = [
      for (final page in pages) PdfPageInput(imagePath: page.exportPath),
    ];

    final useComposite =
        nidCompositeConfig != null &&
        nidCompositeConfig.pdfLayout != NidPdfLayout.separatePages &&
        pages.length <= 2;

    final out = await _runBuild(
      inputs: inputs,
      outputPath: resolvedPath,
      config: cfg,
      nidConfig: useComposite ? nidCompositeConfig : null,
      onProgress: onProgress,
    );

    return ScannedPdfResult(
      pdfPath: out.pdfPath,
      pages: List<ScannedPage>.unmodifiable(pages),
      pageCount: out.pdfPageCount,
      byteLength: out.byteLength,
      sha256: out.sha256,
      generatedAt: out.generatedAt,
    );
  }

  /// Headless helper to build a local `.pdf` directly from arbitrary image files.
  Future<({String pdfPath, int pageCount, int byteLength, String? sha256})>
  buildFromFiles({
    required List<PdfPageInput> pages,
    required String outputFilePath,
    PdfConfig? overrideConfig,
    NidScanConfig? nidCompositeConfig,
    void Function(PdfGenerationProgress progress)? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const PdfGenerationException(
        'Cannot generate a PDF with zero pages.',
      );
    }
    final cfg = overrideConfig ?? config;
    await File(outputFilePath).parent.create(recursive: true);
    final useComposite =
        nidCompositeConfig != null &&
        nidCompositeConfig.pdfLayout != NidPdfLayout.separatePages &&
        pages.length <= 2;

    final out = await _runBuild(
      inputs: pages,
      outputPath: outputFilePath,
      config: cfg,
      nidConfig: useComposite ? nidCompositeConfig : null,
      onProgress: onProgress,
    );
    return (
      pdfPath: out.pdfPath,
      pageCount: out.pdfPageCount,
      byteLength: out.byteLength,
      sha256: out.sha256,
    );
  }

  Future<String> _resolveOutputPath(String? explicitPath, PdfConfig cfg) async {
    final chosen = explicitPath ?? cfg.customOutputFilePath;
    if (chosen != null && chosen.isNotEmpty) {
      await File(chosen).parent.create(recursive: true);
      return chosen;
    }
    final baseDir = cfg.outputDirectoryPath ?? Directory.systemTemp.path;
    await Directory(baseDir).create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(baseDir, '${cfg.fileNamePrefix}$ts.pdf');
  }

  Future<_PdfBuildWorkerOutput> _runBuild({
    required List<PdfPageInput> inputs,
    required String outputPath,
    required PdfConfig config,
    required NidScanConfig? nidConfig,
    required void Function(PdfGenerationProgress progress)? onProgress,
  }) async {
    if (!config.useIsolate) {
      return _buildPdfSyncOrAsync(
        inputs: inputs,
        outputPath: outputPath,
        config: config,
        nidConfig: nidConfig,
        onPageDone: (done, total) => onProgress?.call(
          PdfGenerationProgress(completedPages: done, totalPages: total),
        ),
      );
    }

    final receivePort = ReceivePort();
    final completer = Completer<_PdfBuildWorkerOutput>();
    late final StreamSubscription<Object?> sub;
    sub = receivePort.listen((message) {
      if (message is (int, int)) {
        onProgress?.call(
          PdfGenerationProgress(
            completedPages: message.$1,
            totalPages: message.$2,
          ),
        );
      } else if (message is _PdfBuildWorkerOutput) {
        if (!completer.isCompleted) completer.complete(message);
      } else if (message is (String, String)) {
        if (!completer.isCompleted) {
          completer.completeError(
            PdfGenerationException(message.$1, cause: message.$2),
          );
        }
      }
    });

    try {
      await Isolate.spawn(_pdfIsolateEntry, (
        receivePort.sendPort,
        inputs,
        outputPath,
        config,
        nidConfig,
      ));
      return await completer.future;
    } finally {
      await sub.cancel();
      receivePort.close();
    }
  }
}

class _PdfBuildWorkerOutput {
  const _PdfBuildWorkerOutput({
    required this.pdfPath,
    required this.pdfPageCount,
    required this.byteLength,
    required this.generatedAt,
    this.sha256,
  });

  final String pdfPath;
  final int pdfPageCount;
  final int byteLength;
  final String? sha256;
  final DateTime generatedAt;
}

Future<void> _pdfIsolateEntry(
  (SendPort, List<PdfPageInput>, String, PdfConfig, NidScanConfig?) args,
) async {
  final (port, inputs, outputPath, config, nidConfig) = args;
  try {
    final result = await _buildPdfSyncOrAsync(
      inputs: inputs,
      outputPath: outputPath,
      config: config,
      nidConfig: nidConfig,
      onPageDone: (done, total) => port.send((done, total)),
    );
    port.send(result);
  } on ScannerFailure catch (e) {
    port.send((e.message, e.cause?.toString() ?? ''));
  } on Object catch (e, st) {
    port.send(('Failed to generate local PDF: $e', st.toString()));
  }
}

Future<_PdfBuildWorkerOutput> _buildPdfSyncOrAsync({
  required List<PdfPageInput> inputs,
  required String outputPath,
  required PdfConfig config,
  required NidScanConfig? nidConfig,
  required void Function(int done, int total) onPageDone,
}) async {
  final tmpFile = File(
    '$outputPath.tmp_${DateTime.now().microsecondsSinceEpoch}',
  );
  await tmpFile.parent.create(recursive: true);

  final writer = StreamingPdfWriter(tmpFile);
  final createdAt = DateTime.now();

  try {
    final int pdfPageCount;
    if (nidConfig != null &&
        nidConfig.pdfLayout != NidPdfLayout.separatePages &&
        inputs.length <= 2) {
      final frontRaw = await _encodePageStream(inputs[0].imagePath);
      onPageDone(1, inputs.length);

      PdfEncodedImage? backEncoded;
      if (inputs.length > 1) {
        final backRaw = await _encodePageStream(inputs[1].imagePath);
        backEncoded = (
          encodedStream: backRaw.bytes,
          imageWidth: backRaw.width,
          imageHeight: backRaw.height,
          colorSpace: backRaw.colorSpace,
          filter: backRaw.filter,
          extraQuarterTurns: inputs[1].extraRotationQuarterTurns,
        );
        onPageDone(2, inputs.length);
      }

      writer.addNidCompositePage(
        front: (
          encodedStream: frontRaw.bytes,
          imageWidth: frontRaw.width,
          imageHeight: frontRaw.height,
          colorSpace: frontRaw.colorSpace,
          filter: frontRaw.filter,
          extraQuarterTurns: inputs[0].extraRotationQuarterTurns,
        ),
        back: backEncoded,
        nidConfig: nidConfig,
      );
      pdfPageCount = 1;
    } else {
      for (var i = 0; i < inputs.length; i++) {
        final item = inputs[i];
        final sourceFile = File(item.imagePath);
        if (!await sourceFile.exists()) {
          throw PdfGenerationException(
            'Page ${i + 1} image file is missing (${item.imagePath}).',
          );
        }

        final encoded = await _encodePageStream(item.imagePath);
        writer.addImagePage(
          encodedStream: encoded.bytes,
          imageWidth: encoded.width,
          imageHeight: encoded.height,
          colorSpace: encoded.colorSpace,
          filter: encoded.filter,
          config: config,
          extraQuarterTurns: item.extraRotationQuarterTurns,
        );
        onPageDone(i + 1, inputs.length);
      }
      pdfPageCount = inputs.length;
    }

    final totalBytes = writer.finish(config.metadata, createdAt);

    final finalFile = File(outputPath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tmpFile.rename(outputPath);

    String? digestHex;
    if (config.computeSha256) {
      final digest = await sha256.bind(finalFile.openRead()).first;
      digestHex = digest.toString();
    }

    return _PdfBuildWorkerOutput(
      pdfPath: outputPath,
      pdfPageCount: pdfPageCount,
      byteLength: totalBytes,
      sha256: digestHex,
      generatedAt: createdAt,
    );
  } on Object {
    writer.abort();
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } on Object {
        // Ignore cleanup failure.
      }
    }
    rethrow;
  }
}

typedef _EncodedPdfImage = ({
  Uint8List bytes,
  int width,
  int height,
  String colorSpace,
  String filter,
});

Future<_EncodedPdfImage> _encodePageStream(String imagePath) async {
  final sourceFile = File(imagePath);
  if (!await sourceFile.exists()) {
    throw PdfGenerationException('Image file is missing ($imagePath).');
  }

  final jpegInfo = await orientedJpegInfo(imagePath);
  if (jpegInfo != null &&
      jpegInfo.orientation == 1 &&
      (jpegInfo.components == 1 || jpegInfo.components == 3)) {
    final rawJpeg = await sourceFile.readAsBytes();
    return (
      bytes: rawJpeg,
      width: jpegInfo.rawWidth,
      height: jpegInfo.rawHeight,
      colorSpace: jpegInfo.components == 1 ? '/DeviceGray' : '/DeviceRGB',
      filter: '/DCTDecode',
    );
  }

  final scope = MatScope();
  try {
    final ext = p.extension(imagePath).toLowerCase();
    if (ext == '.png') {
      final mat = scope.add(
        await cv.imreadAsync(imagePath, flags: cv.IMREAD_UNCHANGED),
      );
      if (mat.isEmpty) {
        throw PdfGenerationException('Could not decode PNG page ($imagePath).');
      }
      if (mat.channels == 1) {
        final greyPixels = packGreyBytes(mat);
        final compressed = Uint8List.fromList(zlib.encode(greyPixels));
        return (
          bytes: compressed,
          width: mat.cols,
          height: mat.rows,
          colorSpace: '/DeviceGray',
          filter: '/FlateDecode',
        );
      }
    }

    final bgr = scope.add(await cv.imreadAsync(imagePath));
    if (bgr.isEmpty) {
      throw PdfGenerationException('Could not decode image page ($imagePath).');
    }
    final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]);
    try {
      final (ok, encoded) = await cv.imencodeAsync('.jpg', bgr, params: params);
      if (!ok) {
        throw const PdfGenerationException(
          'Could not encode image stream for PDF.',
        );
      }
      return (
        bytes: encoded,
        width: bgr.cols,
        height: bgr.rows,
        colorSpace: bgr.channels == 1 ? '/DeviceGray' : '/DeviceRGB',
        filter: '/DCTDecode',
      );
    } finally {
      params.dispose();
    }
  } finally {
    scope.dispose();
  }
}
