import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path/path.dart' as p;

import '../../config/pdf_config.dart';
import '../../domain/scanned_page.dart';
import '../../domain/scanned_pdf_result.dart';
import '../../domain/scanner_failure.dart';
import '../crop/jpeg_header.dart';
import '../processing/opencv_support.dart';
import 'streaming_pdf_writer.dart';

/// Input item when calling [LocalPdfBuilder.buildFromFiles] directly without
/// a [CustomScannerController].
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
/// in a background isolate.
///
/// * **Color & Grayscale JPEGs** are embedded directly as `/DCTDecode` streams
///   with zero pixel decoding or re-encoding.
/// * **Black & White 8-bit PNGs** are embedded losslessly as zlib `/FlateDecode`
///   `/DeviceGray` streams so crisp Sauvola text edges never get JPEG artifacts.
class LocalPdfBuilder {
  /// Creates a [LocalPdfBuilder].
  const LocalPdfBuilder({this.config = const PdfConfig()});

  /// PDF layout, output path, and metadata settings.
  final PdfConfig config;

  /// Builds a local `.pdf` file from ordered [ScannedPage] items.
  Future<ScannedPdfResult> buildFromScannedPages({
    required List<ScannedPage> pages,
    String? outputFilePath,
    PdfConfig? overrideConfig,
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
      for (final page in pages)
        // Note: rotationQuarterTurns was already baked into croppedPath/exportPath
        // during perspective crop, so extraRotationQuarterTurns is 0 here.
        PdfPageInput(imagePath: page.exportPath),
    ];

    final out = await _runBuild(
      inputs: inputs,
      outputPath: resolvedPath,
      config: cfg,
      onProgress: onProgress,
    );

    return ScannedPdfResult(
      pdfPath: out.pdfPath,
      pages: List<ScannedPage>.unmodifiable(pages),
      pageCount: pages.length,
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
    void Function(PdfGenerationProgress progress)? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const PdfGenerationException(
        'Cannot generate a PDF with zero pages.',
      );
    }
    final cfg = overrideConfig ?? config;
    await File(outputFilePath).parent.create(recursive: true);
    final out = await _runBuild(
      inputs: pages,
      outputPath: outputFilePath,
      config: cfg,
      onProgress: onProgress,
    );
    return (
      pdfPath: out.pdfPath,
      pageCount: pages.length,
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
    required void Function(PdfGenerationProgress progress)? onProgress,
  }) async {
    if (!config.useIsolate) {
      return _buildPdfSyncOrAsync(
        inputs: inputs,
        outputPath: outputPath,
        config: config,
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
    required this.byteLength,
    required this.generatedAt,
    this.sha256,
  });

  final String pdfPath;
  final int byteLength;
  final String? sha256;
  final DateTime generatedAt;
}

Future<void> _pdfIsolateEntry(
  (SendPort, List<PdfPageInput>, String, PdfConfig) args,
) async {
  final (port, inputs, outputPath, config) = args;
  try {
    final result = await _buildPdfSyncOrAsync(
      inputs: inputs,
      outputPath: outputPath,
      config: config,
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
  required void Function(int done, int total) onPageDone,
}) async {
  final tmpFile = File(
    '$outputPath.tmp_${DateTime.now().microsecondsSinceEpoch}',
  );
  await tmpFile.parent.create(recursive: true);

  final writer = StreamingPdfWriter(tmpFile);
  final createdAt = DateTime.now();

  try {
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
  // Fast path 1: Upright 1-channel or 3-channel JPEG -> zero-re-encode /DCTDecode!
  final jpegInfo = await orientedJpegInfo(imagePath);
  if (jpegInfo != null &&
      jpegInfo.orientation == 1 &&
      (jpegInfo.components == 1 || jpegInfo.components == 3)) {
    final rawJpeg = await File(imagePath).readAsBytes();
    return (
      bytes: rawJpeg,
      width: jpegInfo.rawWidth,
      height: jpegInfo.rawHeight,
      colorSpace: jpegInfo.components == 1 ? '/DeviceGray' : '/DeviceRGB',
      filter: '/DCTDecode',
    );
  }

  // Fast path 2: 8-bit grayscale/B&W PNG (e.g. Sauvola B&W) -> lossless /FlateDecode!
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

    // Fallback path: EXIF-oriented JPEGs (orientation != 1), RGB PNGs, WebP, BMP, etc.
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
