import 'dart:math' as math;

/// A 2D point in pixel or normalized coordinates.
class PagePoint {
  /// Creates a point at ([x], [y]).
  const PagePoint(this.x, this.y);

  /// Deserializes a point from a two-element numeric JSON list `[x, y]`.
  factory PagePoint.fromJson(List<Object?> json) =>
      PagePoint((json[0]! as num).toDouble(), (json[1]! as num).toDouble());

  /// Horizontal coordinate.
  final double x;

  /// Vertical coordinate.
  final double y;

  /// Vector addition.
  PagePoint operator +(PagePoint other) => PagePoint(x + other.x, y + other.y);

  /// Vector subtraction.
  PagePoint operator -(PagePoint other) => PagePoint(x - other.x, y - other.y);

  /// Scales [x] by [sx] and [y] by [sy] (or [sx] when [sy] is omitted).
  PagePoint scale(double sx, [double? sy]) => PagePoint(x * sx, y * (sy ?? sx));

  /// Euclidean distance to [other].
  double distanceTo(PagePoint other) =>
      math.sqrt(_sq(x - other.x) + _sq(y - other.y));

  /// Serializes this point as `[x, y]`.
  List<double> toJson() => [_round(x), _round(y)];

  @override
  bool operator ==(Object other) =>
      other is PagePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';

  static double _sq(double v) => v * v;
  static double _round(double v) => (v * 10).roundToDouble() / 10;
}

/// Four document corners ordered clockwise starting from [topLeft], in the
/// oriented pixel space of the source image.
class CropCorners {
  /// Creates an explicit four-corner quadrilateral.
  const CropCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Quadrilateral covering the entire [width] × [height] image.
  factory CropCorners.full(int width, int height) => CropCorners(
    topLeft: const PagePoint(0, 0),
    topRight: PagePoint(width.toDouble(), 0),
    bottomRight: PagePoint(width.toDouble(), height.toDouble()),
    bottomLeft: PagePoint(0, height.toDouble()),
  );

  /// Orders four arbitrary corner points clockwise starting from top-left.
  factory CropCorners.ordered(List<PagePoint> points) {
    if (points.length != 4) {
      throw ArgumentError.value(points.length, 'points', 'Expected 4 corners');
    }
    final cx = points.fold<double>(0, (s, p) => s + p.x) / 4;
    final cy = points.fold<double>(0, (s, p) => s + p.y) / 4;
    final sorted = [...points]
      ..sort(
        (a, b) => math
            .atan2(a.y - cy, a.x - cx)
            .compareTo(math.atan2(b.y - cy, b.x - cx)),
      );
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
        start = i;
      }
    }
    final ordered = [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
    return CropCorners(
      topLeft: ordered[0],
      topRight: ordered[1],
      bottomRight: ordered[2],
      bottomLeft: ordered[3],
    );
  }

  /// Deserializes corners from JSON.
  factory CropCorners.fromJson(List<Object?> json) => CropCorners(
    topLeft: PagePoint.fromJson(json[0]! as List<Object?>),
    topRight: PagePoint.fromJson(json[1]! as List<Object?>),
    bottomRight: PagePoint.fromJson(json[2]! as List<Object?>),
    bottomLeft: PagePoint.fromJson(json[3]! as List<Object?>),
  );

  /// Top-left page corner.
  final PagePoint topLeft;

  /// Top-right page corner.
  final PagePoint topRight;

  /// Bottom-right page corner.
  final PagePoint bottomRight;

  /// Bottom-left page corner.
  final PagePoint bottomLeft;

  /// All four corners in clockwise order `[topLeft, topRight, bottomRight, bottomLeft]`.
  List<PagePoint> get points => [topLeft, topRight, bottomRight, bottomLeft];

  /// Serializes the four corners as JSON.
  List<List<double>> toJson() => [for (final p in points) p.toJson()];

  /// Scales every corner by ([sx], [sy]).
  CropCorners scaled(double sx, [double? sy]) => CropCorners(
    topLeft: topLeft.scale(sx, sy),
    topRight: topRight.scale(sx, sy),
    bottomRight: bottomRight.scale(sx, sy),
    bottomLeft: bottomLeft.scale(sx, sy),
  );

  /// Expands every corner outward from [centroid] by [fraction] of [meanSide],
  /// clamped to [width] × [height].
  CropCorners withMargin(double fraction, int width, int height) {
    final c = centroid;
    final grow = fraction * meanSide;
    PagePoint push(PagePoint p) {
      final d = p - c;
      final len = math.sqrt(d.x * d.x + d.y * d.y);
      if (len == 0) return p;
      final q = p + PagePoint(d.x / len * grow, d.y / len * grow);
      return PagePoint(
        q.x.clamp(0, width.toDouble()),
        q.y.clamp(0, height.toDouble()),
      );
    }

    return CropCorners(
      topLeft: push(topLeft),
      topRight: push(topRight),
      bottomRight: push(bottomRight),
      bottomLeft: push(bottomLeft),
    );
  }

  /// Clamps every corner into `[0..width, 0..height]`.
  CropCorners clampTo(int width, int height) {
    PagePoint clampPoint(PagePoint p) => PagePoint(
      p.x.clamp(0, width.toDouble()),
      p.y.clamp(0, height.toDouble()),
    );
    return CropCorners(
      topLeft: clampPoint(topLeft),
      topRight: clampPoint(topRight),
      bottomRight: clampPoint(bottomRight),
      bottomLeft: clampPoint(bottomLeft),
    );
  }

  /// Geometric center of the four corners.
  PagePoint get centroid => PagePoint(
    points.fold<double>(0, (s, p) => s + p.x) / 4,
    points.fold<double>(0, (s, p) => s + p.y) / 4,
  );

  /// Mean length of the four edges.
  double get meanSide =>
      (topLeft.distanceTo(topRight) +
          topRight.distanceTo(bottomRight) +
          bottomRight.distanceTo(bottomLeft) +
          bottomLeft.distanceTo(topLeft)) /
      4;

  /// Target upright dimensions `(width, height)` for perspective warping.
  (int width, int height) get outputSize {
    final w = math.max(
      topLeft.distanceTo(topRight),
      bottomLeft.distanceTo(bottomRight),
    );
    final h = math.max(
      topLeft.distanceTo(bottomLeft),
      topRight.distanceTo(bottomRight),
    );
    return (w.round(), h.round());
  }

  /// Shoelace area in square pixels.
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// Whether the quadrilateral is strictly convex without self-intersection.
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) return false;
      final s = cross.sign;
      if (sign != null && s != sign) return false;
      sign = s;
    }
    return true;
  }

  /// Smallest interior corner angle in degrees.
  double get minAngle {
    final p = points;
    var minimum = 180.0;
    for (var i = 0; i < 4; i++) {
      final prev = p[(i + 3) % 4] - p[i];
      final next = p[(i + 1) % 4] - p[i];
      final dot = prev.x * next.x + prev.y * next.y;
      final len =
          math.sqrt(prev.x * prev.x + prev.y * prev.y) *
          math.sqrt(next.x * next.x + next.y * next.y);
      if (len == 0) return 0;
      final angle = math.acos((dot / len).clamp(-1.0, 1.0)) * 180 / math.pi;
      minimum = math.min(minimum, angle);
    }
    return minimum;
  }

  @override
  bool operator ==(Object other) =>
      other is CropCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'CropCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
