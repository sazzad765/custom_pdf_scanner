import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path/path.dart' as p;

/// Generates synthetic document photos (perspective-skewed on a dark desk and
/// pre-cropped pages with shadows, dark text lines, 1px rules, and colored stamps)
/// for deterministic local tests without external image assets.
class SyntheticPageHelper {
  static const int pageW = 600;
  static const int pageH = 800;
  static const int photoW = 1200;
  static const int photoH = 900;

  static const corners = [
    (320.0, 80.0),
    (880.0, 105.0),
    (860.0, 820.0),
    (300.0, 800.0),
  ];

  static Uint8List _buildSheetPixels({
    double shadow = 0.35,
    int markerBand = 0,
  }) {
    final buf = Uint8List(pageW * pageH * 3);
    void setPixel(int x, int y, int b, int g, int r) {
      final i = (y * pageW + x) * 3;
      buf[i] = b;
      buf[i + 1] = g;
      buf[i + 2] = r;
    }

    for (var y = 0; y < pageH; y++) {
      for (var x = 0; x < pageW; x++) {
        setPixel(x, y, 245, 244, 242);
      }
    }

    // Text-like horizontal stroke bars.
    for (var line = 0; line < 14 + (markerBand % 4); line++) {
      final top = 50 + line * 32;
      for (var y = top; y < top + 5; y++) {
        for (var x = 40; x < pageW - 40; x++) {
          if ((x ~/ 6).isEven) setPixel(x, y, 28, 28, 30);
        }
      }
    }

    // Coloured stamp patch at bottom-right.
    for (var y = pageH - 130; y < pageH - 80; y++) {
      for (var x = pageW - 200; x < pageW - 50; x++) {
        if ((x + y) % 7 < 5) setPixel(x, y, 190, 90, 40);
      }
    }

    // Multiplicative uneven shadow from left to right.
    for (var y = 0; y < pageH; y++) {
      for (var x = 0; x < pageW; x++) {
        final f = 1 - shadow * math.pow(1 - x / pageW, 2);
        final idx = (y * pageW + x) * 3;
        buf[idx] = (buf[idx] * f).round();
        buf[idx + 1] = (buf[idx + 1] * f).round();
        buf[idx + 2] = (buf[idx + 2] * f).round();
      }
    }
    return buf;
  }

  /// Writes a pre-cropped synthetic JPEG document page.
  static Future<String> writeCroppedJpeg(
    Directory dir, {
    required String name,
    int markerBand = 0,
  }) async {
    final mat = cv.Mat.fromList(
      pageH,
      pageW,
      cv.MatType.CV_8UC3,
      _buildSheetPixels(markerBand: markerBand),
    );
    final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]);
    try {
      final (_, bytes) = cv.imencode('.jpg', mat, params: params);
      final outPath = p.join(dir.path, name);
      await File(outPath).writeAsBytes(bytes, flush: true);
      return outPath;
    } finally {
      params.dispose();
      mat.dispose();
    }
  }

  /// Writes a synthetic camera photo containing a perspective-skewed document
  /// on a dark desk background.
  static Future<String> writePerspectiveDeskPhoto(
    Directory dir, {
    required String name,
    int markerBand = 0,
  }) async {
    final page = cv.Mat.fromList(
      pageH,
      pageW,
      cv.MatType.CV_8UC3,
      _buildSheetPixels(markerBand: markerBand),
    );
    final desk = cv.Mat.fromScalar(
      photoH,
      photoW,
      cv.MatType.CV_8UC3,
      cv.Scalar(44, 48, 54, 0),
    );
    final src = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(pageW - 1.0, 0),
      cv.Point2f(pageW - 1.0, pageH - 1.0),
      cv.Point2f(0, pageH - 1.0),
    ]);
    final dst = cv.VecPoint2f.fromList([
      for (final c in corners) cv.Point2f(c.$1, c.$2),
    ]);
    final transform = cv.getPerspectiveTransform2f(src, dst);
    final warped = cv.warpPerspective(
      page,
      transform,
      (photoW, photoH),
      dst: desk,
      borderMode: cv.BORDER_TRANSPARENT,
      flags: cv.INTER_LINEAR,
    );
    final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 93]);
    try {
      final (_, bytes) = cv.imencode('.jpg', warped, params: params);
      final outPath = p.join(dir.path, name);
      await File(outPath).writeAsBytes(bytes, flush: true);
      return outPath;
    } finally {
      params.dispose();
      page.dispose();
      transform.dispose();
      src.dispose();
      dst.dispose();
      desk.dispose();
    }
  }
}
