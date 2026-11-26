import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paints a normalized (`0..1`) four-corner document quadrilateral overlay
/// over a camera preview or manual crop image.
class CameraBoundaryOverlay extends StatelessWidget {
  /// Creates a [CameraBoundaryOverlay].
  const CameraBoundaryOverlay({
    required this.corners,
    required this.color,
    this.strokeWidth = 2.5,
    this.dashed = false,
    this.fillColor,
    this.outsideMaskColor,
    super.key,
  });

  /// Four clockwise corners normalized to `[0..1, 0..1]`.
  final List<Offset> corners;

  /// Outline stroke color.
  final Color color;

  /// Outline stroke width in logical pixels.
  final double strokeWidth;

  /// Draws a dashed stroke when `true`.
  final bool dashed;

  /// Optional translucent fill inside the quadrilateral.
  final Color? fillColor;

  /// Optional dark scrim outside the quadrilateral (used in manual crop mode).
  final Color? outsideMaskColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BoundaryPainter(this),
    child: const SizedBox.expand(),
  );
}

class _BoundaryPainter extends CustomPainter {
  _BoundaryPainter(this.overlay);

  final CameraBoundaryOverlay overlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (overlay.corners.length != 4) return;
    final pts = [
      for (final c in overlay.corners)
        Offset(c.dx * size.width, c.dy * size.height),
    ];
    final poly = Path()..addPolygon(pts, true);

    if (overlay.outsideMaskColor != null) {
      final mask = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        poly,
      );
      canvas.drawPath(mask, Paint()..color = overlay.outsideMaskColor!);
    }

    if (overlay.fillColor != null) {
      canvas.drawPath(poly, Paint()..color = overlay.fillColor!);
    }

    final stroke = Paint()
      ..color = overlay.color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = overlay.strokeWidth;
    canvas.drawPath(overlay.dashed ? _dash(poly, 8, 5) : poly, stroke);
  }

  static Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? on : off;
        if (draw) {
          out.addPath(
            metric.extractPath(distance, distance + len),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_BoundaryPainter oldDelegate) =>
      oldDelegate.overlay.corners != overlay.corners ||
      oldDelegate.overlay.color != overlay.color ||
      oldDelegate.overlay.dashed != overlay.dashed ||
      oldDelegate.overlay.fillColor != overlay.fillColor ||
      oldDelegate.overlay.outsideMaskColor != overlay.outsideMaskColor;
}
