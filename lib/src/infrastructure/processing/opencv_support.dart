import 'package:dartcv4/dartcv.dart' as cv;
import 'package:flutter/foundation.dart';

/// Deterministic native `cv.Mat` scope that disposes all owned matrices in
/// reverse allocation order.
class MatScope {
  final _mats = <cv.Mat>[];

  /// Registers [mat] for disposal and returns it.
  cv.Mat add(cv.Mat mat) {
    _mats.add(mat);
    return mat;
  }

  /// Releases [mat] immediately and removes it from this scope.
  void release(cv.Mat mat) {
    if (!_mats.remove(mat)) return;
    try {
      mat.dispose();
    } on Object {
      // Already disposed.
    }
  }

  /// Count of currently tracked live matrices.
  int get liveCount => _mats.length;

  /// Disposes all remaining tracked matrices.
  void dispose() {
    for (final mat in _mats.reversed) {
      try {
        mat.dispose();
      } on Object {
        // Already disposed.
      }
    }
    _mats.clear();
  }
}

/// Returns the smallest odd integer greater than or equal to `max(value, floor)`.
int oddAtLeast(int value, int floor) {
  final raised = value < floor ? floor : value;
  return raised.isEven ? raised + 1 : raised;
}

/// Returns a new `cv.Mat` downscaled with `INTER_AREA` so its long edge does
/// not exceed [maxEdge] (`maxEdge <= 0` clones at full resolution).
Future<cv.Mat> downscaleTo(cv.Mat source, int maxEdge) async {
  if (maxEdge <= 0) return source.clone();
  final longEdge = source.cols > source.rows ? source.cols : source.rows;
  if (longEdge <= maxEdge) return source.clone();
  final scale = maxEdge / longEdge;
  return cv.resizeAsync(source, (
    (source.cols * scale).round(),
    (source.rows * scale).round(),
  ), interpolation: cv.INTER_AREA);
}

/// Extracts tightly packed 8-bit grayscale bytes without row-stride padding.
Uint8List packGreyBytes(cv.Mat mat) {
  final width = mat.cols;
  final height = mat.rows;
  if (mat.isContinuous) {
    return Uint8List.fromList(mat.data.sublist(0, width * height));
  }
  final packed = Uint8List(width * height);
  final source = mat.data;
  final stride = source.length ~/ height;
  for (var row = 0; row < height; row++) {
    packed.setRange(row * width, row * width + width, source, row * stride);
  }
  return packed;
}

/// Coarse photometric profile of a cropped page prior to enhancement.
@immutable
class PageStatistics {
  /// Creates [PageStatistics].
  const PageStatistics({
    required this.paperLevel,
    required this.contrast,
    required this.noise,
    required this.meanSaturation,
    required this.saturationDeviation,
    required this.strongColorFraction,
  });

  /// Mean luminance of the page.
  final double paperLevel;

  /// Luminance standard deviation.
  final double contrast;

  /// High-frequency residual noise estimate.
  final double noise;

  /// Mean HSV saturation across the bright half of the sheet.
  final double meanSaturation;

  /// HSV saturation standard deviation across the page.
  final double saturationDeviation;

  /// Fraction of pixels carrying strong chroma (`S > 72`).
  final double strongColorFraction;
}

/// Measures [PageStatistics] on a small downscaled copy of [source].
Future<PageStatistics> measurePage(cv.Mat source, MatScope scope) async {
  final small = scope.add(await downscaleTo(source, 420));
  final grey = scope.add(
    small.channels == 1
        ? small.clone()
        : await cv.cvtColorAsync(small, cv.COLOR_BGR2GRAY),
  );
  final (mean, stddev) = await cv.meanStdDevAsync(grey);
  final smoothed = scope.add(await cv.gaussianBlurAsync(grey, (3, 3), 0));
  final residual = scope.add(await cv.absDiffAsync(grey, smoothed));
  final (noiseMean, _) = await cv.meanStdDevAsync(residual);
  if (small.channels == 1) {
    return PageStatistics(
      paperLevel: mean.val1,
      contrast: stddev.val1,
      noise: noiseMean.val1,
      meanSaturation: 0,
      saturationDeviation: 0,
      strongColorFraction: 0,
    );
  }
  final hsv = scope.add(await cv.cvtColorAsync(small, cv.COLOR_BGR2HSV));
  final hsvPlanes = await cv.splitAsync(hsv);
  try {
    final brightMask = scope.add(
      (await cv.thresholdAsync(
        grey,
        (mean.val1 * 0.85).clamp(40.0, 235.0),
        255,
        cv.THRESH_BINARY,
      )).$2,
    );
    final (_, saturationStdDev) = await cv.meanStdDevAsync(hsvPlanes[1]);
    final hasBright = cv.countNonZero(brightMask) > grey.rows * grey.cols ~/ 10;
    final (paperSatMean, _) = hasBright
        ? await cv.meanStdDevAsync(hsvPlanes[1], mask: brightMask)
        : await cv.meanStdDevAsync(hsvPlanes[1]);
    final strongColor = scope.add(
      (await cv.thresholdAsync(hsvPlanes[1], 72, 255, cv.THRESH_BINARY)).$2,
    );
    final strongColorFraction =
        cv.countNonZero(strongColor) / (strongColor.rows * strongColor.cols);
    return PageStatistics(
      paperLevel: mean.val1,
      contrast: stddev.val1,
      noise: noiseMean.val1,
      meanSaturation: paperSatMean.val1,
      saturationDeviation: saturationStdDev.val1,
      strongColorFraction: strongColorFraction,
    );
  } finally {
    hsvPlanes.dispose();
  }
}

/// Estimates bright-paper greyscale level of [source].
Future<double> measurePaperLevel(cv.Mat source, MatScope scope) async {
  final small = scope.add(await downscaleTo(source, 360));
  final grey = scope.add(
    small.channels == 1
        ? small.clone()
        : await cv.cvtColorAsync(small, cv.COLOR_BGR2GRAY),
  );
  final (mean, _) = await cv.meanStdDevAsync(grey);
  final bright = scope.add(
    (await cv.thresholdAsync(grey, mean.val1, 255, cv.THRESH_BINARY)).$2,
  );
  final (paper, _) = await cv.meanStdDevAsync(grey, mask: bright);
  return paper.val1 > 0 ? paper.val1 : mean.val1;
}
