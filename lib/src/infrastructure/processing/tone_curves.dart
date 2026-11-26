import 'dart:math' as math;

import 'package:dartcv4/dartcv.dart' as cv;

int _safeByte(double v) {
  if (v.isNaN) return 0;
  if (v.isInfinite) return v.isNegative ? 0 : 255;
  return v.round().clamp(0, 255);
}

/// Builds a 256-entry LUT curve that lifts paper brightness smoothly to white
/// while keeping dark ink below [inkFloor] anchored.
cv.Mat whiteningCurve({
  required double paperLevel,
  required double knee,
  required double whiteMargin,
  required double whitePoint,
  required double inkFloor,
}) {
  final ceiling = (whitePoint * 255).clamp(1.0, 255.0);
  final anchor = math.min(knee * 255 + 8, ceiling);
  final safePaper = paperLevel.isFinite ? paperLevel : 220.0;
  final white = (safePaper * whiteMargin).clamp(anchor, ceiling);
  final kneeLevel = (knee * 255).clamp(0.0, white - 0.5);
  final floor = (inkFloor * 255).clamp(0.0, math.max(0.0, kneeLevel - 1.0));

  final curve = List<int>.generate(256, (value) {
    if (value <= floor) return value;
    if (value >= white) return 255;
    if (value <= kneeLevel) {
      final span = math.max(1e-6, kneeLevel - floor);
      final t = ((value - floor) / span).clamp(0.0, 1.0);
      return _safeByte(floor + span * (0.92 * t + 0.08 * t * t));
    }
    final span = math.max(1e-6, white - kneeLevel);
    final t = ((value - kneeLevel) / span).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    return _safeByte(kneeLevel + (255 - kneeLevel) * eased);
  });

  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, curve);
}

/// Smooth Hermite alpha ramp (`0` at `<= low`, `255` at `>= high`).
cv.Mat confidenceRamp({required int low, required int high}) {
  final lo = low.clamp(0, 254);
  final hi = math.max(lo + 1, high.clamp(1, 255));
  final span = (hi - lo).toDouble();
  final curve = List<int>.generate(256, (value) {
    if (value <= lo) return 0;
    if (value >= hi) return 255;
    final t = ((value - lo) / span).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    return _safeByte(eased * 255);
  });
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, curve);
}

/// Lab lightness tone curve for colored, tinted, or aged sheets.
cv.Mat coloredPageInkCurve({
  required double paperLevel,
  required double strength,
  required double inkFloor,
}) {
  final safePaper = paperLevel.isFinite ? paperLevel : 220.0;
  final floor = (inkFloor * 255).clamp(0.0, 40.0);
  final pivot = math.max(175.0, math.min(228.0, safePaper - 14));
  final targetPaper = math.max(236.0, math.min(245.0, safePaper));
  final k = strength.clamp(0.0, 0.75);
  final inkSpan = math.max(1.0, pivot - floor);

  final curve = List<int>.generate(256, (value) {
    final v = value.toDouble();
    if (v <= floor) return _safeByte(v * 0.75);
    if (v < pivot) {
      final t = ((v - floor) / inkSpan).clamp(0.0, 1.0);
      final pull = k * 4.0 * t * (1 - t) * (1 - 0.35 * t);
      final mapped = floor + inkSpan * (t - pull).clamp(0.0, 1.0);
      return _safeByte(mapped);
    }
    final denom = math.max(1.0, 255.0 - pivot);
    final t = ((v - pivot) / denom).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    final lifted = pivot + (targetPaper - pivot) * eased;
    final tail = math.max(lifted, v);
    return _safeByte(tail).clamp(0, 250);
  });
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, curve);
}

/// HSV saturation LUT boosting intentional color while optionally attenuating
/// weak indoor lighting cast on white paper.
cv.Mat saturationCurve(double gain, {bool cleanNeutralPaper = false}) {
  final safeGain = gain.isFinite ? gain : 1.0;
  final curve = List<int>.generate(256, (value) {
    if (!cleanNeutralPaper) {
      if (value <= 10) return value;
      return _safeByte(10 + (value - 10) * safeGain);
    }
    if (value <= 24) {
      return _safeByte(value * 0.48);
    }
    if (value < 42) {
      final t = ((value - 24) / 18.0).clamp(0.0, 1.0);
      final low = value * 0.48;
      final high = 18 + (value - 18) * safeGain;
      return _safeByte(low + (high - low) * t * t * (3 - 2 * t));
    }
    return _safeByte(18 + (value - 18) * safeGain);
  });
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, curve);
}

/// Lab lightness curve for multi-color artwork, letterheads, and forms.
cv.Mat artworkLuminanceCurve() {
  final curve = List<int>.generate(256, (value) {
    final x = (value / 255.0).clamp(0.0, 1.0);
    if (x <= 0.45) {
      final t = (x / 0.45).clamp(0.0, 1.0);
      final darkened = 0.45 * math.pow(t, 1.28);
      return _safeByte(darkened * 255);
    }
    final t = ((x - 0.45) / 0.55).clamp(0.0, 1.0);
    final inv = (1.0 - t).clamp(0.0, 1.0);
    final lifted = 0.45 + 0.55 * (1.0 - math.pow(inv, 1.35));
    return _safeByte(lifted * 255);
  });
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, curve);
}
