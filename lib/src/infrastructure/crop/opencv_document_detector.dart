import 'dart:math' as math;

import 'package:dartcv4/dartcv.dart' as cv;

import '../../config/processing_config.dart';
import '../../domain/crop_corners.dart';
import '../../domain/crop_models.dart';
import '../processing/opencv_support.dart';
import 'document_detector.dart';
import 'jpeg_header.dart';

/// OpenCV document quadrilateral detector combining adaptive Canny edge search
/// and Otsu paper-brightness segmentation with surround-contrast verification.
class OpenCvDocumentDetector implements DocumentDetector {
  /// Creates an [OpenCvDocumentDetector] configured via [config].
  const OpenCvDocumentDetector({this.config = const ProcessingConfig()});

  /// Processing & detection configuration.
  final ProcessingConfig config;

  @override
  Future<DetectionResult> detectFile(String imagePath) async {
    final scope = MatScope();
    try {
      var reduced = scope.add(
        await cv.imreadAsync(imagePath, flags: cv.IMREAD_REDUCED_GRAYSCALE_4),
      );
      if (reduced.isEmpty) {
        scope.release(reduced);
        reduced = scope.add(
          await cv.imreadAsync(imagePath, flags: cv.IMREAD_GRAYSCALE),
        );
      }
      if (reduced.isEmpty) {
        throw StateError('Image could not be decoded for corner detection');
      }
      final size =
          await orientedJpegSize(imagePath) ?? await _fullSize(imagePath);
      return await _detect(reduced, size.$1, size.$2, scope);
    } finally {
      scope.dispose();
    }
  }

  @override
  Future<DetectionResult> detectFrame(LumaFrame frame) async {
    final scope = MatScope();
    try {
      var grey = scope.add(
        cv.Mat.fromList(
          frame.height,
          frame.width,
          cv.MatType.CV_8UC1,
          frame.bytes,
        ),
      );
      final code = switch (frame.rotationDegrees % 360) {
        90 => cv.ROTATE_90_CLOCKWISE,
        180 => cv.ROTATE_180,
        270 => cv.ROTATE_90_COUNTERCLOCKWISE,
        _ => null,
      };
      if (code != null) grey = scope.add(await cv.rotateAsync(grey, code));
      return await _detect(grey, grey.cols, grey.rows, scope);
    } finally {
      scope.dispose();
    }
  }

  Future<(int, int)> _fullSize(String path) async {
    final m = await cv.imreadAsync(path, flags: cv.IMREAD_GRAYSCALE);
    try {
      return (m.cols, m.rows);
    } finally {
      m.dispose();
    }
  }

  Future<DetectionResult> _detect(
    cv.Mat grey,
    int targetWidth,
    int targetHeight,
    MatScope scope,
  ) async {
    final small = scope.add(
      await downscaleTo(grey, config.detectionAnalysisEdge),
    );
    final blurred = scope.add(await cv.gaussianBlurAsync(small, (5, 5), 0));
    final frameArea = (small.cols * small.rows).toDouble();

    final candidates = <_Candidate>[];

    // Pass 1: Canny edges + morphological close.
    final median = _median(blurred);
    final lower = math.max(10.0, 0.66 * median);
    final upper = math.min(255.0, math.max(lower + 20, 1.33 * median));
    final edges = scope.add(await cv.cannyAsync(blurred, lower, upper));
    final closeKernel = scope.add(
      await cv.getStructuringElementAsync(cv.MORPH_RECT, (5, 5)),
    );
    final closed = scope.add(
      await cv.morphologyExAsync(
        edges,
        cv.MORPH_CLOSE,
        closeKernel,
        iterations: 2,
      ),
    );
    await _collect(closed, frameArea, candidates);

    // Pass 2: Bright paper blob via Otsu thresholding.
    final (_, otsu) = await cv.thresholdAsync(
      blurred,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    scope.add(otsu);
    final whiteShare = cv.countNonZero(otsu) / frameArea;
    if (whiteShare > 0.02 && whiteShare < 0.99) {
      final blobKernel = scope.add(
        await cv.getStructuringElementAsync(cv.MORPH_RECT, (9, 9)),
      );
      final paper = scope.add(
        await cv.morphologyExAsync(
          otsu,
          cv.MORPH_CLOSE,
          blobKernel,
          borderType: cv.BORDER_REPLICATE,
        ),
      );
      await _collect(paper, frameArea, candidates);
    }

    for (var i = 0; i < candidates.length; i++) {
      final contrast = _contrast(blurred, candidates[i].points, scope);
      if (contrast == null) continue;
      if (contrast < config.minContrast) {
        candidates[i] = candidates[i].penalised(0.5);
      }
    }

    if (candidates.isEmpty) {
      return DetectionResult.none(
        imageWidth: targetWidth,
        imageHeight: targetHeight,
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = candidates.first;

    final sx = targetWidth / small.cols;
    final sy = targetHeight / small.rows;
    final corners = CropCorners.ordered(
      best.points,
    ).scaled(sx, sy).clampTo(targetWidth, targetHeight);

    final issues = <CropIssue>[
      if (best.confidence < config.minCropConfidence) CropIssue.lowConfidence,
      if (best.areaRatio < config.minAreaRatio) CropIssue.tooSmall,
      if (!corners.isConvex) CropIssue.notConvex,
      if (corners.minAngle < config.minCornerAngle) CropIssue.sharpAngle,
    ];
    return DetectionResult(
      corners: corners,
      confidence: best.confidence,
      imageWidth: targetWidth,
      imageHeight: targetHeight,
      issues: issues,
    );
  }

  double? _contrast(cv.Mat grey, List<PagePoint> quad, MatScope scope) {
    final inside = scope.add(
      cv.Mat.zeros(grey.rows, grey.cols, cv.MatType.CV_8UC1),
    );
    final pts = cv.VecVecPoint.fromList([
      [for (final p in quad) cv.Point(p.x.round(), p.y.round())],
    ]);
    cv.fillPoly(inside, pts, cv.Scalar.all(255));
    pts.dispose();
    final band = math.max(3, (math.min(grey.rows, grey.cols) * 0.04).round());
    final kernel = scope.add(
      cv.getStructuringElement(cv.MORPH_RECT, (band * 2 + 1, band * 2 + 1)),
    );
    final grown = scope.add(cv.dilate(inside, kernel));
    final ring = scope.add(cv.subtract(grown, inside));
    final ringPixels = cv.countNonZero(ring);
    if (ringPixels < grey.rows * grey.cols * 0.005) return null;
    final a = cv.mean(grey, mask: inside).val1;
    final b = cv.mean(grey, mask: ring).val1;
    return (a - b).abs();
  }

  double _median(cv.Mat grey) {
    final data = grey.data;
    final hist = List<int>.filled(256, 0);
    final step = math.max(1, data.length ~/ 20000);
    var n = 0;
    for (var i = 0; i < data.length; i += step) {
      hist[data[i]]++;
      n++;
    }
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= n / 2) return v.toDouble();
    }
    return 128;
  }

  Future<void> _collect(
    cv.Mat binary,
    double frameArea,
    List<_Candidate> out,
  ) async {
    final (contours, hierarchy) = await cv.findContoursAsync(
      binary,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );
    try {
      for (final contour in contours) {
        final area = await cv.contourAreaAsync(contour);
        final ratio = area / frameArea;
        if (ratio < config.minAreaRatio * 0.6 || ratio > config.maxAreaRatio) {
          continue;
        }
        final perimeter = await cv.arcLengthAsync(contour, true);
        List<PagePoint>? quad;
        for (final f in const [0.02, 0.03, 0.045]) {
          final poly = await cv.approxPolyDPAsync(contour, f * perimeter, true);
          try {
            if (poly.length == 4 && cv.isContourConvex(poly)) {
              quad = [
                for (final p in poly) PagePoint(p.x.toDouble(), p.y.toDouble()),
              ];
              break;
            }
          } finally {
            poly.dispose();
          }
        }
        var rectangularity = 1.0;
        if (quad == null) {
          final rect = await cv.minAreaRectAsync(contour);
          final box = cv.boxPoints(rect);
          final pts = [for (final p in box) PagePoint(p.x, p.y)];
          box.dispose();
          final boxArea = CropCorners.ordered(pts).area;
          rectangularity = boxArea == 0 ? 0 : area / boxArea;
          if (rectangularity < 0.85) continue;
          quad = pts;
          rectangularity *= 0.8;
        } else {
          final quadArea = CropCorners.ordered(quad).area;
          rectangularity = quadArea == 0 ? 0 : math.min(1, area / quadArea);
        }
        final ordered = CropCorners.ordered(quad);
        final angleScore = ((ordered.minAngle - 45) / 35).clamp(0.0, 1.0);
        final sizeScore = ((ratio - 0.15) / 0.45).clamp(0.0, 1.0);
        out.add(
          _Candidate(
            points: quad,
            areaRatio: ratio,
            confidence:
                0.45 * sizeScore + 0.35 * rectangularity + 0.2 * angleScore,
          ),
        );
      }
    } finally {
      contours.dispose();
      hierarchy.dispose();
    }
  }
}

class _Candidate {
  const _Candidate({
    required this.points,
    required this.areaRatio,
    required this.confidence,
  });

  final List<PagePoint> points;
  final double areaRatio;
  final double confidence;

  _Candidate penalised(double factor) => _Candidate(
    points: points,
    areaRatio: areaRatio,
    confidence: confidence * factor,
  );
}
