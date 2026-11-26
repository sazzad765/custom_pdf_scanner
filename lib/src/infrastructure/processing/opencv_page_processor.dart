import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartcv4/dartcv.dart' as cv;

import '../../config/processing_config.dart';
import '../../domain/scan_filter.dart';
import '../crop/jpeg_header.dart';
import 'opencv_support.dart';
import 'page_quality_evaluator.dart';
import 'tone_curves.dart';

/// Output of enhancing a single cropped page via [OpenCvPageProcessor].
class PageEnhancementResult {
  /// Creates a [PageEnhancementResult].
  const PageEnhancementResult({
    required this.outputPath,
    required this.filter,
    required this.width,
    required this.height,
    this.thumbnailWritten = false,
    this.usedFallback = false,
    this.failureReason,
    this.captureMetrics = const {},
    this.outputMetrics = const {},
    this.checksum,
    this.byteLength,
  });

  /// File path of the processed page (or `croppedPath` when `usedFallback` or `original`/`natural`).
  final String outputPath;

  /// Filter that was requested.
  final ScanFilter filter;

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// True when a thumbnail was written to `thumbnailOutputPath`.
  final bool thumbnailWritten;

  /// True if OpenCV threw an unexpected error and fell back safely to `croppedPath`.
  final bool usedFallback;

  /// Diagnostic error reason when [usedFallback] is `true`.
  final String? failureReason;

  /// Raw pre-enhancement quality measurements.
  final Map<String, double> captureMetrics;

  /// Raw post-enhancement validation measurements.
  final Map<String, double> outputMetrics;

  /// SHA-256 hex digest of [outputPath].
  final String? checksum;

  /// Byte size of [outputPath].
  final int? byteLength;
}

/// Headless & controller-ready OpenCV page enhancement processor supporting
/// both single-page isolate execution and sequential multi-page batch processing.
class OpenCvPageProcessor {
  /// Creates an [OpenCvPageProcessor] with [config].
  const OpenCvPageProcessor({this.config = const ProcessingConfig()});

  /// Processing parameters.
  final ProcessingConfig config;

  /// Enhances a single perspective-cropped page at [croppedPath] using [filter]
  /// and writes the result to [outputPath] (plus optional [thumbnailOutputPath]).
  Future<PageEnhancementResult> processPage({
    required String croppedPath,
    required ScanFilter filter,
    required String outputPath,
    String? thumbnailOutputPath,
    bool? includeCaptureMetrics,
  }) {
    final cfg = config;
    final measureCapture = includeCaptureMetrics ?? cfg.enableQualityChecks;
    Future<PageEnhancementResult> run() => _Pipeline(cfg).runFull(
      croppedPath: croppedPath,
      filter: filter,
      outputPath: outputPath,
      thumbnailOutputPath: thumbnailOutputPath,
      includeCaptureMetrics: measureCapture,
    );
    return cfg.useIsolate ? Isolate.run(run) : run();
  }

  /// Processes a batch of cropped pages sequentially (keeping peak memory bounded
  /// to a single page at a time) and reports progress after each page.
  Future<List<PageEnhancementResult>> processBatch({
    required List<
      ({String croppedPath, String outputPath, String? thumbnailPath})
    >
    items,
    ScanFilter? filter,
    void Function(int completed, int total, PageEnhancementResult latest)?
    onProgress,
  }) async {
    final chosenFilter = filter ?? config.defaultFilter;
    final results = <PageEnhancementResult>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final res = await processPage(
        croppedPath: item.croppedPath,
        filter: chosenFilter,
        outputPath: item.outputPath,
        thumbnailOutputPath: item.thumbnailPath,
      );
      results.add(res);
      onProgress?.call(i + 1, items.length, res);
    }
    return results;
  }

  /// Writes a compact thumbnail JPEG from [sourcePath] to [outputPath].
  Future<void> writeThumbnail({
    required String sourcePath,
    required String outputPath,
  }) {
    final cfg = config;
    Future<void> run() => _writeThumbnailFromFile(cfg, sourcePath, outputPath);
    return cfg.useIsolate ? Isolate.run(run) : run();
  }
}

Future<Uint8List> _encodeMat(
  cv.Mat image, {
  required String ext,
  required List<int> params,
}) async {
  final vec = cv.VecI32.fromList(params);
  try {
    final (ok, bytes) = await cv.imencodeAsync(ext, image, params: vec);
    if (!ok) throw StateError('Image could not be encoded ($ext)');
    return bytes;
  } finally {
    vec.dispose();
  }
}

Future<cv.Mat> _mergeChannels(List<cv.Mat> channels) async {
  final vec = cv.VecMat.fromList(channels);
  try {
    return await cv.mergeAsync(vec);
  } finally {
    vec.dispose();
  }
}

Future<void> _writeThumbnailFromMat(
  ProcessingConfig cfg,
  cv.Mat source,
  String output,
  MatScope scope,
) async {
  final small = scope.add(await downscaleTo(source, cfg.thumbnailEdge));
  try {
    final bytes = await _encodeMat(
      small,
      ext: '.jpg',
      params: [cv.IMWRITE_JPEG_QUALITY, cfg.thumbnailQuality],
    );
    await File(output).parent.create(recursive: true);
    await File(output).writeAsBytes(bytes, flush: true);
  } finally {
    scope.release(small);
  }
}

Future<void> _writeThumbnailFromFile(
  ProcessingConfig cfg,
  String source,
  String output,
) async {
  final scope = MatScope();
  try {
    var image = scope.add(
      await cv.imreadAsync(source, flags: cv.IMREAD_REDUCED_COLOR_4),
    );
    if (image.isEmpty) {
      scope.release(image);
      image = scope.add(await cv.imreadAsync(source));
    }
    if (image.isEmpty) {
      throw StateError('Thumbnail source could not be decoded');
    }
    await _writeThumbnailFromMat(cfg, image, output, scope);
  } finally {
    scope.dispose();
  }
}

class _Pipeline {
  _Pipeline(this.options);

  final ProcessingConfig options;

  Future<PageEnhancementResult> runFull({
    required String croppedPath,
    required ScanFilter filter,
    required String outputPath,
    required String? thumbnailOutputPath,
    required bool includeCaptureMetrics,
  }) async {
    if (filter == ScanFilter.original) {
      var thumbWritten = false;
      if (thumbnailOutputPath != null) {
        try {
          await _writeThumbnailFromFile(
            options,
            croppedPath,
            thumbnailOutputPath,
          );
          thumbWritten = true;
        } on Object {
          thumbWritten = false;
        }
      }
      final size = await orientedJpegSize(croppedPath) ?? (0, 0);
      final rawBytes = await File(croppedPath).readAsBytes();
      return PageEnhancementResult(
        outputPath: croppedPath,
        filter: filter,
        width: size.$1,
        height: size.$2,
        thumbnailWritten: thumbWritten,
        checksum: sha256.convert(rawBytes).toString(),
        byteLength: rawBytes.length,
      );
    }

    final scope = MatScope();
    var captureMetrics = const <String, double>{};
    try {
      final decoded = scope.add(await cv.imreadAsync(croppedPath));
      if (decoded.isEmpty) {
        throw StateError('Cropped page could not be decoded');
      }
      if (includeCaptureMetrics) {
        try {
          captureMetrics = await measureCaptureMat(
            decoded,
            options.qualityAnalysisEdge,
            scope,
          );
        } on Object {
          captureMetrics = const {};
        }
      }

      final source = scope.add(await downscaleTo(decoded, options.maxLongEdge));
      scope.release(decoded);

      final pageStats = await measurePage(source, scope);

      if (filter == ScanFilter.natural) {
        final metrics = options.enableQualityChecks
            ? await _validate(source, source, pageStats, true, scope)
            : const <String, double>{};
        var thumbWritten = false;
        if (thumbnailOutputPath != null) {
          try {
            await _writeThumbnailFromMat(
              options,
              source,
              thumbnailOutputPath,
              scope,
            );
            thumbWritten = true;
          } on Object {
            thumbWritten = false;
          }
        }
        String? checksum;
        int? byteLength;
        try {
          final rawBytes = await File(croppedPath).readAsBytes();
          checksum = sha256.convert(rawBytes).toString();
          byteLength = rawBytes.length;
        } on Object {
          // Optional hash fallback.
        }
        return PageEnhancementResult(
          outputPath: croppedPath,
          filter: filter,
          width: source.cols,
          height: source.rows,
          thumbnailWritten: thumbWritten,
          captureMetrics: captureMetrics,
          outputMetrics: metrics,
          checksum: checksum,
          byteLength: byteLength,
        );
      }

      final processed = await _process(source, filter, pageStats, scope);
      final png = filter == ScanFilter.blackAndWhite;
      final encoded = await _encodeMat(
        processed,
        ext: png ? '.png' : '.jpg',
        params: png
            ? [cv.IMWRITE_PNG_COMPRESSION, options.pngCompression]
            : [cv.IMWRITE_JPEG_QUALITY, options.jpegQuality],
      );
      final metrics = options.enableQualityChecks
          ? await _validate(
              source,
              processed,
              pageStats,
              encoded.isNotEmpty,
              scope,
            )
          : const <String, double>{};
      scope.release(source);

      final out = File(outputPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(encoded, flush: true);

      final checksum = sha256.convert(encoded).toString();
      final byteLength = encoded.length;

      var thumbWritten = false;
      if (thumbnailOutputPath != null) {
        try {
          await _writeThumbnailFromMat(
            options,
            processed,
            thumbnailOutputPath,
            scope,
          );
          thumbWritten = true;
        } on Object {
          thumbWritten = false;
        }
      }
      return PageEnhancementResult(
        outputPath: outputPath,
        filter: filter,
        width: processed.cols,
        height: processed.rows,
        thumbnailWritten: thumbWritten,
        captureMetrics: captureMetrics,
        outputMetrics: metrics,
        checksum: checksum,
        byteLength: byteLength,
      );
    } on Object catch (error) {
      var thumbWritten = false;
      if (thumbnailOutputPath != null) {
        try {
          await _writeThumbnailFromFile(
            options,
            croppedPath,
            thumbnailOutputPath,
          );
          thumbWritten = true;
        } on Object {
          thumbWritten = false;
        }
      }
      final fallbackSize = await orientedJpegSize(croppedPath) ?? (0, 0);
      return PageEnhancementResult(
        outputPath: croppedPath,
        filter: filter,
        width: fallbackSize.$1,
        height: fallbackSize.$2,
        thumbnailWritten: thumbWritten,
        usedFallback: true,
        failureReason: error.toString(),
        captureMetrics: captureMetrics,
      );
    } finally {
      scope.dispose();
    }
  }

  Future<Map<String, double>> _validate(
    cv.Mat input,
    cv.Mat output,
    PageStatistics pageStats,
    bool decodable,
    MatScope scope,
  ) async {
    final m = <String, double>{
      'out_decodable': decodable ? 1.0 : 0.0,
      'out_width': output.cols.toDouble(),
      'out_height': output.rows.toDouble(),
    };

    Future<cv.Mat> grey(cv.Mat src) async {
      final small = scope.add(await downscaleTo(src, 800));
      if (small.channels == 1) return small;
      final g = scope.add(await cv.cvtColorAsync(small, cv.COLOR_BGR2GRAY));
      scope.release(small);
      return g;
    }

    final gi = await grey(input);
    final go = await grey(output);
    final (meanIn, stdIn) = await cv.meanStdDevAsync(gi);
    final (meanOut, stdOut) = await cv.meanStdDevAsync(go);
    m['in_mean'] = meanIn.val1;
    m['out_mean'] = meanOut.val1;
    m['in_std'] = stdIn.val1;
    m['out_std'] = stdOut.val1;
    m['out_paper'] = await measurePaperLevel(go, scope);
    m['color_artwork'] =
        pageStats.saturationDeviation >= options.colorArtworkDeviationTrigger &&
            pageStats.strongColorFraction >= options.colorArtworkFractionTrigger
        ? 1
        : 0;
    m['colored_page'] =
        pageStats.meanSaturation >= options.coloredPaperSaturationTrigger
        ? 1
        : 0;

    final total = (gi.rows * gi.cols).toDouble();
    Future<double> fraction(cv.Mat g, int threshold, int type) async {
      final t = scope.add(
        (await cv.thresholdAsync(g, threshold.toDouble(), 255, type)).$2,
      );
      final ratio = cv.countNonZero(t) / total;
      scope.release(t);
      return ratio;
    }

    m['in_black'] = await fraction(gi, 8, cv.THRESH_BINARY_INV);
    m['out_black'] = await fraction(go, 8, cv.THRESH_BINARY_INV);
    m['out_white'] = await fraction(go, 249, cv.THRESH_BINARY);

    Future<double> ink(cv.Mat g) async {
      final t = scope.add(
        await cv.adaptiveThresholdAsync(
          g,
          255,
          cv.ADAPTIVE_THRESH_MEAN_C,
          cv.THRESH_BINARY_INV,
          25,
          15,
        ),
      );
      final ratio = cv.countNonZero(t) / total;
      scope.release(t);
      return ratio;
    }

    m['in_ink'] = await ink(gi);
    m['out_ink'] = await ink(go);

    final a = scope.add(
      await cv.resizeAsync(gi, (160, 160), interpolation: cv.INTER_AREA),
    );
    final b = scope.add(
      await cv.resizeAsync(go, (160, 160), interpolation: cv.INTER_AREA),
    );
    final corr = scope.add(
      await cv.matchTemplateAsync(a, b, cv.TM_CCOEFF_NORMED),
    );
    final v = corr.at<double>(0, 0);
    m['correlation'] = v.isNaN ? 1 : v;
    scope.release(corr);
    scope.release(a);
    scope.release(b);
    scope.release(gi);
    scope.release(go);
    return m;
  }

  Future<cv.Mat> _process(
    cv.Mat source,
    ScanFilter filter,
    PageStatistics stats,
    MatScope scope,
  ) async {
    if (filter == ScanFilter.magicColor &&
        stats.saturationDeviation >= options.colorArtworkDeviationTrigger &&
        stats.strongColorFraction >= options.colorArtworkFractionTrigger) {
      return _processColorArtwork(source, stats, scope);
    }

    if (filter == ScanFilter.magicColor &&
        stats.meanSaturation >= options.coloredPaperSaturationTrigger) {
      return _processColoredPaper(source, stats, scope);
    }

    var working = scope.add(await _flattenIllumination(source, scope));

    if (options.denoise && stats.noise > options.noiseTrigger) {
      final denoised = scope.add(
        await cv.bilateralFilterAsync(
          working,
          5,
          options.denoiseStrength.toDouble(),
          options.denoiseStrength.toDouble(),
        ),
      );
      scope.release(working);
      working = denoised;
    }

    final enhanced = scope.add(await _enhanceText(working, stats, scope));
    scope.release(working);
    working = enhanced;

    cv.Mat? foreground;
    if (options.backgroundRefinement) {
      foreground = scope.add(await _foregroundMask(working, scope));
      if (options.residualShadowRemoval) {
        final lifted = scope.add(
          await _correctResidualShadow(working, foreground, scope),
        );
        scope.release(working);
        working = lifted;
      }
    }

    final paper = await measurePaperLevel(working, scope);
    final whitened = scope.add(
      await _whitenPaper(working, paper, foreground, scope),
    );
    scope.release(working);
    if (foreground != null) scope.release(foreground);
    working = whitened;

    if (options.speckleRemoval) {
      final despeckled = scope.add(await _removeSpeckles(working, scope));
      scope.release(working);
      working = despeckled;
    }

    return switch (filter) {
      ScanFilter.blackAndWhite => () async {
        final grey = scope.add(
          working.channels == 1
              ? working.clone()
              : await cv.cvtColorAsync(working, cv.COLOR_BGR2GRAY),
        );
        scope.release(working);
        final bw = scope.add(await _sauvolaBlackWhite(grey));
        scope.release(grey);
        return bw;
      }(),
      ScanFilter.grayscale => () async {
        final grey = scope.add(
          working.channels == 1
              ? working.clone()
              : await cv.cvtColorAsync(working, cv.COLOR_BGR2GRAY),
        );
        scope.release(working);
        return grey;
      }(),
      _ => working,
    };
  }

  Future<cv.Mat> _processColorArtwork(
    cv.Mat source,
    PageStatistics stats,
    MatScope scope,
  ) async {
    final normalized = scope.add(
      await _normalizeArtworkIllumination(source, stats, scope),
    );
    final vivid = scope.add(
      await _boostArtworkColor(normalized, scope, cleanNeutralPaper: true),
    );
    scope.release(normalized);
    final toned = scope.add(await _toneArtwork(vivid, scope));
    scope.release(vivid);

    final sharpened = scope.add(
      await _enhanceText(
        toned,
        stats,
        scope,
        forceClahe: true,
        claheClipScale: 1.2,
        sharpenScale: 1.55,
      ),
    );
    final smoothPaper = scope.add(await _smoothArtworkSurface(toned, scope));
    final detailAlpha = scope.add(await _artworkDetailMask(toned, scope));
    scope.release(toned);

    final invAlpha = scope.add(await cv.bitwiseNOTAsync(detailAlpha));
    final alpha3 = scope.add(
      await _mergeChannels([detailAlpha, detailAlpha, detailAlpha]),
    );
    final inv3 = scope.add(
      await _mergeChannels([invAlpha, invAlpha, invAlpha]),
    );
    scope.release(detailAlpha);
    scope.release(invAlpha);

    final fgPart = scope.add(
      await cv.multiplyAsync(sharpened, alpha3, scale: 1 / 255),
    );
    final bgPart = scope.add(
      await cv.multiplyAsync(smoothPaper, inv3, scale: 1 / 255),
    );
    scope.release(sharpened);
    scope.release(smoothPaper);
    scope.release(alpha3);
    scope.release(inv3);

    final result = scope.add(await cv.addAsync(fgPart, bgPart));
    scope.release(fgPart);
    scope.release(bgPart);
    return result;
  }

  Future<cv.Mat> _normalizeArtworkIllumination(
    cv.Mat source,
    PageStatistics stats,
    MatScope scope,
  ) async {
    final smallBgr = scope.add(
      await downscaleTo(source, options.backgroundEstimateEdge),
    );
    final smallLab = scope.add(
      await cv.cvtColorAsync(smallBgr, cv.COLOR_BGR2Lab),
    );
    final smallHsv = scope.add(
      await cv.cvtColorAsync(smallBgr, cv.COLOR_BGR2HSV),
    );
    scope.release(smallBgr);

    cv.Mat bgFull;
    final smallLabPlanes = await cv.splitAsync(smallLab);
    final smallHsvPlanes = await cv.splitAsync(smallHsv);
    scope.release(smallLab);
    scope.release(smallHsv);
    try {
      final smallL = smallLabPlanes[0];
      final smallS = smallHsvPlanes[1];
      final paperRef = await measurePaperLevel(smallL, scope);

      final satMask = scope.add(
        (await cv.thresholdAsync(smallS, 52, 255, cv.THRESH_BINARY)).$2,
      );
      final darkCutoff = (paperRef * 0.78).clamp(80.0, 210.0);
      final darkMask = scope.add(
        (await cv.thresholdAsync(
          smallL,
          darkCutoff,
          255,
          cv.THRESH_BINARY_INV,
        )).$2,
      );
      final nonPaper = scope.add(await cv.bitwiseORAsync(satMask, darkMask));
      scope.release(satMask);
      scope.release(darkMask);

      final paperOnlyL = scope.add(smallL.clone());
      paperOnlyL.setTo(cv.Scalar.all(paperRef), mask: nonPaper);
      scope.release(nonPaper);

      final shortEdge = math.min(paperOnlyL.cols, paperOnlyL.rows);
      final blurSize = oddAtLeast(shortEdge ~/ 3, 21);
      final smoothBg = scope.add(
        await cv.gaussianBlurAsync(
          paperOnlyL,
          (blurSize, blurSize),
          0,
          borderType: cv.BORDER_REPLICATE,
        ),
      );
      scope.release(paperOnlyL);
      bgFull = scope.add(
        await cv.resizeAsync(smoothBg, (
          source.cols,
          source.rows,
        ), interpolation: cv.INTER_LINEAR),
      );
      scope.release(smoothBg);
    } finally {
      smallLabPlanes.dispose();
      smallHsvPlanes.dispose();
    }

    final lab = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2Lab));
    final planes = await cv.splitAsync(lab);
    scope.release(lab);
    try {
      final lightness = planes[0];
      final corrected = scope.add(
        await cv.divideAsync(lightness, bgFull, scale: 244),
      );
      scope.release(bgFull);
      final blended = scope.add(
        await cv.addWeightedAsync(lightness, 0.14, corrected, 0.86, 0),
      );
      scope.release(corrected);
      final merged = await _mergeChannels([blended, planes[1], planes[2]]);
      scope.release(blended);
      try {
        return await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
      } finally {
        merged.dispose();
      }
    } finally {
      planes.dispose();
    }
  }

  Future<cv.Mat> _smoothArtworkSurface(cv.Mat source, MatScope scope) async {
    final small = scope.add(
      await downscaleTo(source, options.tintedBackgroundEdge),
    );
    final smooth = scope.add(await cv.bilateralFilterAsync(small, 7, 20, 20));
    scope.release(small);
    final up = await cv.resizeAsync(smooth, (
      source.cols,
      source.rows,
    ), interpolation: cv.INTER_LINEAR);
    scope.release(smooth);
    return up;
  }

  Future<cv.Mat> _artworkDetailMask(cv.Mat source, MatScope scope) async {
    final grey = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2GRAY));
    final clean = scope.add(
      await cv.gaussianBlurAsync(
        grey,
        (3, 3),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(grey);

    final shortEdge = math.min(clean.cols, clean.rows);
    final localSize = oddAtLeast((shortEdge / 36).round().clamp(15, 45), 15);
    final localMean = scope.add(
      await cv.gaussianBlurAsync(
        clean,
        (localSize, localSize),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    final localDiff = scope.add(await cv.absDiffAsync(clean, localMean));
    scope.release(localMean);

    final edgeKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (3, 3)),
    );
    final gradient = scope.add(
      await cv.morphologyExAsync(clean, cv.MORPH_GRADIENT, edgeKernel),
    );
    scope.release(clean);

    final signal = scope.add(await cv.maxAsync(localDiff, gradient));
    scope.release(localDiff);
    scope.release(gradient);

    final ramp = scope.add(confidenceRamp(low: 6, high: 22));
    final rawAlpha = scope.add(await cv.LUTAsync(signal, ramp));
    scope.release(signal);
    scope.release(ramp);

    final grown = scope.add(await cv.dilateAsync(rawAlpha, edgeKernel));
    scope.release(edgeKernel);
    final feathered = await cv.gaussianBlurAsync(
      grown,
      (5, 5),
      0,
      borderType: cv.BORDER_REPLICATE,
    );
    scope.release(grown);
    scope.release(rawAlpha);
    return feathered;
  }

  Future<cv.Mat> _processColoredPaper(
    cv.Mat source,
    PageStatistics stats,
    MatScope scope,
  ) async {
    final lab = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2Lab));
    final planes = await cv.splitAsync(lab);
    scope.release(lab);

    cv.Mat recombined;
    try {
      final rawL = planes[0];
      final rawA = planes[1];
      final rawB = planes[2];

      final bgL = scope.add(await _estimateBackgroundGrey(rawL, scope));
      final dividedL = scope.add(await cv.divideAsync(rawL, bgL, scale: 242));
      scope.release(bgL);
      final blend = options.coloredPaperLightnessBlend.clamp(0.0, 1.0);
      var workL = scope.add(
        await cv.addWeightedAsync(rawL, 1 - blend, dividedL, blend, 0),
      );
      scope.release(dividedL);

      final smoothA = scope.add(
        await cv.gaussianBlurAsync(
          rawA,
          (5, 5),
          1.2,
          borderType: cv.BORDER_REPLICATE,
        ),
      );
      final smoothB = scope.add(
        await cv.gaussianBlurAsync(
          rawB,
          (5, 5),
          1.2,
          borderType: cv.BORDER_REPLICATE,
        ),
      );

      final alpha = scope.add(await _coloredPaperConfidenceMask(workL, scope));

      if (options.backgroundRefinement && options.residualShadowRemoval) {
        final fgGuard = scope.add(
          (await cv.thresholdAsync(alpha, 48, 255, cv.THRESH_BINARY)).$2,
        );
        final liftedL = scope.add(
          await _correctResidualShadowGrey(workL, fgGuard, scope),
        );
        scope.release(fgGuard);
        scope.release(workL);
        workL = liftedL;
      }

      final paperL = await measurePaperLevel(workL, scope);
      final fgL = scope.add(
        await _enhanceColoredPageLightness(workL, paperL, scope),
      );
      final bgSmoothL = scope.add(await _smoothTintedLightness(workL, scope));
      scope.release(workL);

      final invAlpha = scope.add(await cv.bitwiseNOTAsync(alpha));
      final fgPart = scope.add(
        await cv.multiplyAsync(fgL, alpha, scale: 1 / 255),
      );
      final bgPart = scope.add(
        await cv.multiplyAsync(bgSmoothL, invAlpha, scale: 1 / 255),
      );
      final finalL = scope.add(await cv.addAsync(fgPart, bgPart));
      scope.release(alpha);
      scope.release(invAlpha);
      scope.release(fgL);
      scope.release(bgSmoothL);
      scope.release(fgPart);
      scope.release(bgPart);

      final mergedLab = await _mergeChannels([finalL, smoothA, smoothB]);
      scope.release(finalL);
      scope.release(smoothA);
      scope.release(smoothB);
      try {
        recombined = scope.add(
          await cv.cvtColorAsync(mergedLab, cv.COLOR_Lab2BGR),
        );
      } finally {
        mergedLab.dispose();
      }
    } finally {
      planes.dispose();
    }

    var result = scope.add(
      await _boostArtworkColor(
        recombined,
        scope,
        gain: options.tintedPaperSaturationBoost,
      ),
    );
    scope.release(recombined);

    if (options.speckleRemoval) {
      final cleaned = scope.add(
        await _removeSpeckles(result, scope, fillWithLocalBackground: true),
      );
      scope.release(result);
      result = cleaned;
    }
    return result;
  }

  Future<cv.Mat> _estimateBackgroundGrey(cv.Mat grey, MatScope scope) async {
    final small = scope.add(
      await downscaleTo(grey, options.backgroundEstimateEdge),
    );
    final shortEdge = small.cols < small.rows ? small.cols : small.rows;
    final kernelSize = oddAtLeast(
      shortEdge ~/ options.backgroundKernelDivisor,
      9,
    );
    final kernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (
        kernelSize,
        kernelSize,
      )),
    );
    final closed = scope.add(
      await cv.morphologyExAsync(
        small,
        cv.MORPH_CLOSE,
        kernel,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(small);
    scope.release(kernel);
    final blurRadius = oddAtLeast(
      shortEdge ~/ options.backgroundBlurDivisor,
      9,
    );
    final smooth = scope.add(
      await cv.gaussianBlurAsync(
        closed,
        (blurRadius, blurRadius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(closed);
    final background = await cv.resizeAsync(smooth, (
      grey.cols,
      grey.rows,
    ), interpolation: cv.INTER_LINEAR);
    scope.release(smooth);
    return background;
  }

  Future<cv.Mat> _coloredPaperConfidenceMask(
    cv.Mat lightness,
    MatScope scope,
  ) async {
    final clean = scope.add(
      await cv.gaussianBlurAsync(
        lightness,
        (3, 3),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    final small = scope.add(await downscaleTo(clean, 1000));
    final shortSmall = small.cols < small.rows ? small.cols : small.rows;
    final closeSize = oddAtLeast(shortSmall ~/ 26, 11);
    final closeKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (
        closeSize,
        closeSize,
      )),
    );
    final closedSmall = scope.add(
      await cv.morphologyExAsync(
        small,
        cv.MORPH_CLOSE,
        closeKernel,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(small);
    scope.release(closeKernel);
    final blurSize = oddAtLeast(shortSmall ~/ 18, 13);
    final smoothSmall = scope.add(
      await cv.gaussianBlurAsync(
        closedSmall,
        (blurSize, blurSize),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(closedSmall);
    final localBg = scope.add(
      await cv.resizeAsync(smoothSmall, (
        lightness.cols,
        lightness.rows,
      ), interpolation: cv.INTER_LINEAR),
    );
    scope.release(smoothSmall);

    final localDrop = scope.add(await cv.subtractAsync(localBg, clean));
    scope.release(localBg);

    final edgeKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (3, 3)),
    );
    final gradient = scope.add(
      await cv.morphologyExAsync(clean, cv.MORPH_GRADIENT, edgeKernel),
    );
    scope.release(clean);
    final gradScaled = scope.add(
      await gradient.convertToAsync(cv.MatType.CV_8UC1, alpha: 0.75),
    );
    scope.release(gradient);

    final signal = scope.add(await cv.maxAsync(localDrop, gradScaled));
    scope.release(localDrop);
    scope.release(gradScaled);

    final ramp = scope.add(
      confidenceRamp(
        low: options.coloredPaperContrastFloor,
        high: options.coloredPaperContrastCeiling,
      ),
    );
    final rawAlpha = scope.add(await cv.LUTAsync(signal, ramp));
    scope.release(signal);
    scope.release(ramp);

    final grown = scope.add(await cv.dilateAsync(rawAlpha, edgeKernel));
    scope.release(edgeKernel);
    final feathered = scope.add(
      await cv.gaussianBlurAsync(
        grown,
        (5, 5),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(grown);
    final halo = scope.add(
      await feathered.convertToAsync(cv.MatType.CV_8UC1, alpha: 0.55),
    );
    scope.release(feathered);
    final alpha = await cv.maxAsync(rawAlpha, halo);
    scope.release(rawAlpha);
    scope.release(halo);
    return alpha;
  }

  Future<cv.Mat> _enhanceColoredPageLightness(
    cv.Mat lightness,
    double paperLevel,
    MatScope scope,
  ) async {
    final tiles = (lightness.cols / 320).round().clamp(4, 12);
    final clahe = cv.CLAHE.create(options.claheClipLimit, (tiles, tiles));
    var working = scope.add(clahe.apply(lightness));
    clahe.dispose();

    final curve = scope.add(
      coloredPageInkCurve(
        paperLevel: paperLevel,
        strength: options.coloredPaperInkStrength,
        inkFloor: options.inkFloor,
      ),
    );
    final darkened = scope.add(await cv.LUTAsync(working, curve));
    scope.release(curve);
    scope.release(working);
    working = darkened;

    final shortEdge = math.min(lightness.cols, lightness.rows);
    final lowResBoost = shortEdge < 1300 ? 1.2 : 1.0;
    final sharpenAmount = options.sharpenAmount * 1.35 * lowResBoost;
    if (sharpenAmount <= 0) return working.clone();

    final radius = (shortEdge / 1800)
        .clamp(options.sharpenRadiusMin, 1.35)
        .toDouble();
    final blurred = scope.add(
      await cv.gaussianBlurAsync(working, (0, 0), radius),
    );
    final sharpened = await cv.addWeightedAsync(
      working,
      1 + sharpenAmount,
      blurred,
      -sharpenAmount,
      0,
    );
    scope.release(blurred);
    scope.release(working);
    return sharpened;
  }

  Future<cv.Mat> _smoothTintedLightness(
    cv.Mat lightness,
    MatScope scope,
  ) async {
    final small = scope.add(
      await downscaleTo(lightness, options.tintedBackgroundEdge),
    );
    final bilateral = scope.add(
      await cv.bilateralFilterAsync(small, 7, 22, 22),
    );
    scope.release(small);
    final resized = await cv.resizeAsync(bilateral, (
      lightness.cols,
      lightness.rows,
    ), interpolation: cv.INTER_LINEAR);
    scope.release(bilateral);
    return resized;
  }

  Future<cv.Mat> _correctResidualShadowGrey(
    cv.Mat source,
    cv.Mat foreground,
    MatScope scope,
  ) async {
    final small = scope.add(
      await downscaleTo(source, options.residualShadowEdge),
    );
    final smallForeground = scope.add(
      await cv.resizeAsync(foreground, (
        small.cols,
        small.rows,
      ), interpolation: cv.INTER_NEAREST),
    );
    final background = scope.add(await cv.bitwiseNOTAsync(smallForeground));
    scope.release(smallForeground);
    final masked = scope.add(cv.Mat.zeros(small.rows, small.cols, small.type));
    small.copyTo(masked, mask: background);
    scope.release(small);

    final radius = oddAtLeast(masked.cols ~/ 4, 9);
    final blurredContent = scope.add(
      await cv.gaussianBlurAsync(
        masked,
        (radius, radius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(masked);
    final coverage = scope.add(
      await cv.gaussianBlurAsync(
        background,
        (radius, radius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(background);
    final floor = scope.add(
      cv.Mat.fromScalar(
        coverage.rows,
        coverage.cols,
        coverage.type,
        cv.Scalar.all(options.minCoverage.toDouble()),
      ),
    );
    final guarded = scope.add(await cv.maxAsync(coverage, floor));
    scope.release(floor);
    final field = scope.add(
      await cv.divideAsync(blurredContent, guarded, scale: 255),
    );
    scope.release(blurredContent);
    scope.release(guarded);

    final target = scope.add(
      cv.Mat.fromScalar(field.rows, field.cols, field.type, cv.Scalar.all(242)),
    );
    final rawLift = scope.add(await cv.subtractAsync(target, field));
    scope.release(target);
    scope.release(field);
    final ceiling = scope.add(
      cv.Mat.fromScalar(
        rawLift.rows,
        rawLift.cols,
        rawLift.type,
        cv.Scalar.all(options.maxResidualLift.toDouble()),
      ),
    );
    final cappedLift = scope.add(await cv.minAsync(rawLift, ceiling));
    scope.release(rawLift);
    scope.release(ceiling);
    final lift = scope.add(
      await cv.multiplyAsync(cappedLift, coverage, scale: 1 / 255),
    );
    scope.release(cappedLift);
    scope.release(coverage);
    final fullLift = scope.add(
      await cv.resizeAsync(lift, (
        source.cols,
        source.rows,
      ), interpolation: cv.INTER_LINEAR),
    );
    scope.release(lift);

    final lifted = await cv.addAsync(source, fullLift);
    scope.release(fullLift);
    source.copyTo(lifted, mask: foreground);
    return lifted;
  }

  Future<cv.Mat> _sauvolaBlackWhite(cv.Mat grey) async {
    final owned = <cv.Mat>[];
    cv.Mat keep(cv.Mat mat) {
      owned.add(mat);
      return mat;
    }

    try {
      final longEdge = grey.cols > grey.rows ? grey.cols : grey.rows;
      final statsGrey = longEdge <= options.blackWhiteStatsEdge
          ? keep(grey.clone())
          : keep(
              await cv.resizeAsync(grey, (
                (grey.cols * options.blackWhiteStatsEdge / longEdge).round(),
                (grey.rows * options.blackWhiteStatsEdge / longEdge).round(),
              ), interpolation: cv.INTER_AREA),
            );
      final shortEdge = statsGrey.cols < statsGrey.rows
          ? statsGrey.cols
          : statsGrey.rows;
      final window = oddAtLeast(
        (shortEdge / options.blackWhiteWindowDivisor).round().clamp(
          options.blackWhiteMinWindow,
          options.blackWhiteMaxWindow,
        ),
        options.blackWhiteMinWindow,
      );

      final mean = keep(
        await cv.boxFilterAsync(statsGrey, cv.MatType.CV_32F, (
          window,
          window,
        ), borderType: cv.BORDER_REPLICATE),
      );
      final meanSquares = keep(
        await cv.sqrBoxFilterAsync(statsGrey, cv.MatType.CV_32F, (
          window,
          window,
        ), borderType: cv.BORDER_REPLICATE),
      );
      final squaredMean = keep(await cv.multiplyAsync(mean, mean));
      final variance = keep(await cv.subtractAsync(meanSquares, squaredMean));
      final zero = keep(
        cv.Mat.fromScalar(
          statsGrey.rows,
          statsGrey.cols,
          cv.MatType.CV_32FC1,
          cv.Scalar.all(0),
        ),
      );
      final stableVariance = keep(await cv.maxAsync(variance, zero));
      final deviation = keep(await cv.sqrtAsync(stableVariance));

      final base = keep(
        await mean.convertToAsync(
          cv.MatType.CV_32FC1,
          alpha: 1 - options.blackWhiteSauvolaK,
        ),
      );
      final contrast = keep(
        await cv.multiplyAsync(
          mean,
          deviation,
          scale: options.blackWhiteSauvolaK / options.blackWhiteDynamicRange,
        ),
      );
      final threshold = keep(await cv.addAsync(base, contrast));
      final thresholdByte = keep(
        await threshold.convertToAsync(cv.MatType.CV_8UC1),
      );
      final thresholdFull = keep(
        await cv.resizeAsync(thresholdByte, (
          grey.cols,
          grey.rows,
        ), interpolation: cv.INTER_LINEAR),
      );

      return await cv.compareAsync(grey, thresholdFull, cv.CMP_GT);
    } finally {
      for (final mat in owned.reversed) {
        mat.dispose();
      }
    }
  }

  Future<cv.Mat> _boostArtworkColor(
    cv.Mat source,
    MatScope scope, {
    double? gain,
    bool cleanNeutralPaper = false,
  }) async {
    final hsv = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2HSV));
    final planes = await cv.splitAsync(hsv);
    scope.release(hsv);
    try {
      final curve = scope.add(
        saturationCurve(
          gain ?? options.colorArtworkSaturationBoost,
          cleanNeutralPaper: cleanNeutralPaper,
        ),
      );
      final boosted = scope.add(await cv.LUTAsync(planes[1], curve));
      scope.release(curve);
      final merged = await _mergeChannels([planes[0], boosted, planes[2]]);
      scope.release(boosted);
      try {
        return await cv.cvtColorAsync(merged, cv.COLOR_HSV2BGR);
      } finally {
        merged.dispose();
      }
    } finally {
      planes.dispose();
    }
  }

  Future<cv.Mat> _toneArtwork(cv.Mat source, MatScope scope) async {
    final lab = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2Lab));
    final planes = await cv.splitAsync(lab);
    scope.release(lab);
    try {
      final curve = scope.add(artworkLuminanceCurve());
      final lightness = scope.add(await cv.LUTAsync(planes[0], curve));
      scope.release(curve);
      final merged = await _mergeChannels([lightness, planes[1], planes[2]]);
      scope.release(lightness);
      try {
        return await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
      } finally {
        merged.dispose();
      }
    } finally {
      planes.dispose();
    }
  }

  Future<cv.Mat> _flattenIllumination(cv.Mat source, MatScope scope) async {
    final small = scope.add(
      await downscaleTo(source, options.backgroundEstimateEdge),
    );
    final shortEdge = small.cols < small.rows ? small.cols : small.rows;
    final kernelSize = oddAtLeast(
      shortEdge ~/ options.backgroundKernelDivisor,
      9,
    );
    final kernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (
        kernelSize,
        kernelSize,
      )),
    );
    final closed = scope.add(
      await cv.morphologyExAsync(
        small,
        cv.MORPH_CLOSE,
        kernel,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(small);
    scope.release(kernel);
    final blurRadius = oddAtLeast(
      shortEdge ~/ options.backgroundBlurDivisor,
      9,
    );
    final smoothed = scope.add(
      await cv.gaussianBlurAsync(
        closed,
        (blurRadius, blurRadius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(closed);
    final background = scope.add(
      await cv.resizeAsync(smoothed, (
        source.cols,
        source.rows,
      ), interpolation: cv.INTER_LINEAR),
    );
    scope.release(smoothed);
    final divided = await cv.divideAsync(source, background, scale: 255);
    scope.release(background);
    return divided;
  }

  Future<cv.Mat> _enhanceText(
    cv.Mat source,
    PageStatistics stats,
    MatScope scope, {
    bool allowClahe = true,
    bool forceClahe = false,
    double claheClipScale = 1,
    double sharpenScale = 1,
  }) async {
    final shortEdge = math.min(source.cols, source.rows);
    final lowResCapture = shortEdge < 1300;
    final wantsClahe =
        allowClahe &&
        (forceClahe ||
            lowResCapture ||
            stats.contrast < options.claheContrastTrigger);
    final sharpenAmount =
        options.sharpenAmount * sharpenScale * (lowResCapture ? 1.2 : 1.0);
    final wantsSharpen = sharpenAmount > 0;
    if (!wantsClahe && !wantsSharpen) return source.clone();

    if (source.channels == 1) {
      var lightness = source.clone();
      if (wantsClahe) {
        final tiles = (source.cols / 320).round().clamp(4, 12);
        final clahe = cv.CLAHE.create(options.claheClipLimit * claheClipScale, (
          tiles,
          tiles,
        ));
        try {
          final eq = clahe.apply(lightness);
          lightness.dispose();
          lightness = eq;
        } finally {
          clahe.dispose();
        }
      }
      if (wantsSharpen) {
        final radius = (shortEdge / 1800)
            .clamp(
              options.sharpenRadiusMin,
              math.max(options.sharpenRadiusMax, 1.35),
            )
            .toDouble();
        final blurred = await cv.gaussianBlurAsync(lightness, (0, 0), radius);
        try {
          final sharp = await cv.addWeightedAsync(
            lightness,
            1 + sharpenAmount,
            blurred,
            -sharpenAmount,
            0,
          );
          lightness.dispose();
          lightness = sharp;
        } finally {
          blurred.dispose();
        }
      }
      return lightness;
    }

    final lab = scope.add(await cv.cvtColorAsync(source, cv.COLOR_BGR2Lab));
    final planes = await cv.splitAsync(lab);
    scope.release(lab);
    final owned = <cv.Mat>[];
    cv.Mat? recombined;
    try {
      var lightness = planes[0];

      if (wantsClahe) {
        final tiles = (source.cols / 320).round().clamp(4, 12);
        final clahe = cv.CLAHE.create(options.claheClipLimit * claheClipScale, (
          tiles,
          tiles,
        ));
        try {
          final equalised = clahe.apply(lightness);
          owned.add(equalised);
          lightness = equalised;
        } finally {
          clahe.dispose();
        }
      }

      if (wantsSharpen) {
        final radius = (shortEdge / 1800)
            .clamp(
              options.sharpenRadiusMin,
              math.max(options.sharpenRadiusMax, 1.35),
            )
            .toDouble();
        final blurred = await cv.gaussianBlurAsync(lightness, (0, 0), radius);
        try {
          final sharpened = await cv.addWeightedAsync(
            lightness,
            1 + sharpenAmount,
            blurred,
            -sharpenAmount,
            0,
          );
          owned.add(sharpened);
          lightness = sharpened;
        } finally {
          blurred.dispose();
        }
      }

      recombined = await _mergeChannels([lightness, planes[1], planes[2]]);
      return await cv.cvtColorAsync(recombined, cv.COLOR_Lab2BGR);
    } finally {
      recombined?.dispose();
      for (final mat in owned.reversed) {
        mat.dispose();
      }
      planes.dispose();
    }
  }

  Future<cv.Mat> _foregroundMask(cv.Mat source, MatScope scope) async {
    final grey = scope.add(
      source.channels == 1
          ? source.clone()
          : await cv.cvtColorAsync(source, cv.COLOR_BGR2GRAY),
    );
    final dark = scope.add(
      (await cv.thresholdAsync(
        grey,
        options.foregroundDarkLevel.toDouble(),
        255,
        cv.THRESH_BINARY_INV,
      )).$2,
    );
    final edgeKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (3, 3)),
    );
    final gradient = scope.add(
      await cv.morphologyExAsync(grey, cv.MORPH_GRADIENT, edgeKernel),
    );
    scope.release(grey);
    scope.release(edgeKernel);
    final edges = scope.add(
      (await cv.thresholdAsync(
        gradient,
        options.foregroundEdgeLevel.toDouble(),
        255,
        cv.THRESH_BINARY,
      )).$2,
    );
    scope.release(gradient);
    final combined = scope.add(await cv.bitwiseORAsync(dark, edges));
    scope.release(dark);
    scope.release(edges);
    final guard = oddAtLeast(options.foregroundGuard * 2 + 1, 3);
    final guardKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (guard, guard)),
    );
    final dilated = await cv.dilateAsync(combined, guardKernel);
    scope.release(combined);
    scope.release(guardKernel);
    return dilated;
  }

  Future<cv.Mat> _correctResidualShadow(
    cv.Mat source,
    cv.Mat foreground,
    MatScope scope,
  ) async {
    if (source.channels == 1) {
      return _correctResidualShadowGrey(source, foreground, scope);
    }
    final small = scope.add(
      await downscaleTo(source, options.residualShadowEdge),
    );
    final smallForeground = scope.add(
      await cv.resizeAsync(foreground, (
        small.cols,
        small.rows,
      ), interpolation: cv.INTER_NEAREST),
    );
    final background = scope.add(await cv.bitwiseNOTAsync(smallForeground));
    scope.release(smallForeground);
    final masked = scope.add(cv.Mat.zeros(small.rows, small.cols, small.type));
    small.copyTo(masked, mask: background);
    scope.release(small);

    final radius = oddAtLeast(masked.cols ~/ 4, 9);
    final blurredContent = scope.add(
      await cv.gaussianBlurAsync(
        masked,
        (radius, radius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(masked);
    final coverage = scope.add(
      await cv.gaussianBlurAsync(
        background,
        (radius, radius),
        0,
        borderType: cv.BORDER_REPLICATE,
      ),
    );
    scope.release(background);
    final floor = scope.add(
      cv.Mat.fromScalar(
        coverage.rows,
        coverage.cols,
        coverage.type,
        cv.Scalar.all(options.minCoverage.toDouble()),
      ),
    );
    final guarded = scope.add(await cv.maxAsync(coverage, floor));
    scope.release(floor);
    final guarded3 = scope.add(
      await _mergeChannels([guarded, guarded, guarded]),
    );
    scope.release(guarded);
    final field = scope.add(
      await cv.divideAsync(blurredContent, guarded3, scale: 255),
    );
    scope.release(blurredContent);
    scope.release(guarded3);

    final white = scope.add(
      cv.Mat.fromScalar(field.rows, field.cols, field.type, cv.Scalar.all(255)),
    );
    final rawLift = scope.add(await cv.subtractAsync(white, field));
    scope.release(white);
    scope.release(field);
    final ceiling = scope.add(
      cv.Mat.fromScalar(
        rawLift.rows,
        rawLift.cols,
        rawLift.type,
        cv.Scalar.all(options.maxResidualLift.toDouble()),
      ),
    );
    final cappedLift = scope.add(await cv.minAsync(rawLift, ceiling));
    scope.release(rawLift);
    scope.release(ceiling);
    final confidence = scope.add(
      await _mergeChannels([coverage, coverage, coverage]),
    );
    scope.release(coverage);
    final lift = scope.add(
      await cv.multiplyAsync(cappedLift, confidence, scale: 1 / 255),
    );
    scope.release(cappedLift);
    scope.release(confidence);
    final fullLift = scope.add(
      await cv.resizeAsync(lift, (
        source.cols,
        source.rows,
      ), interpolation: cv.INTER_LINEAR),
    );
    scope.release(lift);

    final lifted = await cv.addAsync(source, fullLift);
    scope.release(fullLift);
    source.copyTo(lifted, mask: foreground);
    return lifted;
  }

  Future<cv.Mat> _whitenPaper(
    cv.Mat source,
    double paperLevel,
    cv.Mat? foreground,
    MatScope scope,
  ) async {
    final gentleCurve = scope.add(
      whiteningCurve(
        paperLevel: paperLevel,
        knee: options.paperKnee,
        whiteMargin: options.paperWhiteMargin,
        whitePoint: options.paperWhitePoint,
        inkFloor: options.inkFloor,
      ),
    );
    final gentle = scope.add(await cv.LUTAsync(source, gentleCurve));
    scope.release(gentleCurve);
    if (foreground == null) {
      final copy = gentle.clone();
      scope.release(gentle);
      return copy;
    }
    final strongCurve = scope.add(
      whiteningCurve(
        paperLevel: paperLevel,
        knee: options.backgroundKnee,
        whiteMargin: options.paperWhiteMargin,
        whitePoint: options.paperWhitePoint,
        inkFloor: options.inkFloor,
      ),
    );
    final strong = await cv.LUTAsync(source, strongCurve);
    scope.release(strongCurve);
    gentle.copyTo(strong, mask: foreground);
    scope.release(gentle);
    return strong;
  }

  Future<cv.Mat> _removeSpeckles(
    cv.Mat source,
    MatScope scope, {
    bool fillWithLocalBackground = false,
  }) async {
    final grey = scope.add(
      source.channels == 1
          ? source.clone()
          : await cv.cvtColorAsync(source, cv.COLOR_BGR2GRAY),
    );
    final ink = scope.add(
      (await cv.thresholdAsync(
        grey,
        options.inkMaskLevel.toDouble(),
        255,
        cv.THRESH_BINARY_INV,
      )).$2,
    );
    final joinKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (3, 3)),
    );
    final joined = scope.add(await cv.dilateAsync(ink, joinKernel));
    scope.release(joinKernel);

    final labels = scope.add(cv.Mat.empty());
    final stats = scope.add(cv.Mat.empty());
    final centroids = scope.add(cv.Mat.empty());
    final count = await cv.connectedComponentsWithStatsAsync(
      joined,
      labels,
      stats,
      centroids,
      8,
      cv.MatType.CV_32SC1.value,
      cv.CCL_DEFAULT,
    );
    scope.release(joined);
    scope.release(centroids);
    if (count <= 1) {
      scope.release(grey);
      scope.release(ink);
      scope.release(labels);
      scope.release(stats);
      return source.clone();
    }

    final pixels = source.rows * source.cols;
    final limit = (pixels * options.speckleAreaFraction).round().clamp(
      options.minSpeckleArea,
      options.maxSpeckleArea,
    );
    final inkBytes = ink.data;
    final greyBytes = grey.data;
    final rawLabelBytes = labels.data;
    final labelData = rawLabelBytes.buffer.asInt32List(
      rawLabelBytes.offsetInBytes,
      rawLabelBytes.lengthInBytes ~/ 4,
    );
    final width = source.cols;
    final faintLimit = options.backgroundRefinement
        ? options.maxFaintSpeckleArea
        : limit;
    final examineLimit = faintLimit > limit ? faintLimit : limit;
    final dilatedExamineLimit = examineLimit * 4;

    final doomed = <int>[];
    for (var label = 1; label < count; label++) {
      if (stats.at<int>(label, cv.CC_STAT_AREA) > dilatedExamineLimit) continue;
      final left = stats.at<int>(label, cv.CC_STAT_LEFT);
      final top = stats.at<int>(label, cv.CC_STAT_TOP);
      final right = left + stats.at<int>(label, cv.CC_STAT_WIDTH);
      final bottom = top + stats.at<int>(label, cv.CC_STAT_HEIGHT);
      var inkArea = 0;
      var brightnessSum = 0;
      for (var y = top; y < bottom && inkArea <= examineLimit; y++) {
        final row = y * width;
        for (var x = left; x < right; x++) {
          final offset = row + x;
          if (labelData[offset] == label && inkBytes[offset] != 0) {
            inkArea++;
            brightnessSum += greyBytes[offset];
          }
        }
      }
      if (inkArea == 0 || inkArea > examineLimit) continue;
      final faint = brightnessSum / inkArea > options.faintSpeckleLevel;
      if (inkArea <= (faint ? faintLimit : limit)) doomed.add(label);
    }
    scope.release(grey);
    scope.release(ink);
    if (doomed.isEmpty) {
      scope.release(labels);
      scope.release(stats);
      return source.clone();
    }

    final mask = scope.add(
      cv.Mat.zeros(source.rows, source.cols, cv.MatType.CV_8UC1),
    );
    final maskData = mask.data;
    for (final label in doomed) {
      final left = stats.at<int>(label, cv.CC_STAT_LEFT);
      final top = stats.at<int>(label, cv.CC_STAT_TOP);
      final right = left + stats.at<int>(label, cv.CC_STAT_WIDTH);
      final bottom = top + stats.at<int>(label, cv.CC_STAT_HEIGHT);
      for (var y = top; y < bottom; y++) {
        final row = y * width;
        for (var x = left; x < right; x++) {
          final offset = row + x;
          if (labelData[offset] == label) maskData[offset] = 255;
        }
      }
    }
    scope.release(labels);
    scope.release(stats);

    final cleaned = source.clone();
    if (fillWithLocalBackground) {
      final small = scope.add(await downscaleTo(source, 480));
      final blurred = scope.add(
        await cv.gaussianBlurAsync(
          small,
          (9, 9),
          0,
          borderType: cv.BORDER_REPLICATE,
        ),
      );
      scope.release(small);
      final fill = scope.add(
        await cv.resizeAsync(blurred, (
          source.cols,
          source.rows,
        ), interpolation: cv.INTER_LINEAR),
      );
      scope.release(blurred);
      fill.copyTo(cleaned, mask: mask);
      scope.release(fill);
    } else {
      cleaned.setTo(cv.Scalar.all(255), mask: mask);
    }
    scope.release(mask);
    return cleaned;
  }
}
