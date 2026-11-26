import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dartcv4/dartcv.dart' as cv;

import '../../domain/crop_corners.dart';
import '../processing/opencv_support.dart';
import 'jpeg_header.dart';
import 'perspective_cropper.dart';

/// OpenCV cubic perspective cropper running on a background isolate.
///
/// Automatically fast-paths pre-cropped full-frame upright JPEGs (e.g. from
/// ML Kit Base mode) via zero-decode file copy when already within `maxLongEdge`.
class OpenCvPerspectiveCropper implements PerspectiveCropper {
  /// Creates an [OpenCvPerspectiveCropper].
  const OpenCvPerspectiveCropper({this.useIsolate = true});

  /// Runs perspective warping in a background isolate when `true`.
  final bool useIsolate;

  @override
  Future<CropOutput> crop({
    required String originalPath,
    required CropCorners corners,
    required int quarterTurns,
    required String outputPath,
    required int maxLongEdge,
    required int jpegQuality,
  }) async {
    final turns = quarterTurns % 4;
    if (turns == 0) {
      final info = await orientedJpegInfo(originalPath);
      if (info != null &&
          info.orientation == 1 &&
          _isFullImage(corners, info.width, info.height) &&
          info.width >= 64 &&
          info.height >= 64) {
        final aspect = info.width / info.height;
        if (aspect >= 0.15 &&
            aspect <= 6.5 &&
            (maxLongEdge <= 0 ||
                math.max(info.width, info.height) <= maxLongEdge)) {
          final out = File(outputPath);
          await out.parent.create(recursive: true);
          if (originalPath != outputPath) {
            await File(originalPath).copy(outputPath);
          }
          return (width: info.width, height: info.height);
        }
      }
    }

    Future<CropOutput> run() => _crop(
      originalPath,
      corners,
      turns,
      outputPath,
      maxLongEdge,
      jpegQuality,
    );
    return useIsolate ? Isolate.run(run) : run();
  }

  @override
  Future<(int, int)> imageSize(String path) async {
    final header = await orientedJpegSize(path);
    if (header != null) return header;
    final m = await cv.imreadAsync(path, flags: cv.IMREAD_GRAYSCALE);
    try {
      return (m.cols, m.rows);
    } finally {
      m.dispose();
    }
  }
}

bool _isFullImage(CropCorners corners, int width, int height) {
  const eps = 1.5;
  return corners.topLeft.x.abs() <= eps &&
      corners.topLeft.y.abs() <= eps &&
      (corners.topRight.x - width).abs() <= eps &&
      corners.topRight.y.abs() <= eps &&
      (corners.bottomRight.x - width).abs() <= eps &&
      (corners.bottomRight.y - height).abs() <= eps &&
      corners.bottomLeft.x.abs() <= eps &&
      (corners.bottomLeft.y - height).abs() <= eps;
}

Future<CropOutput> _crop(
  String originalPath,
  CropCorners corners,
  int turns,
  String outputPath,
  int maxLongEdge,
  int jpegQuality,
) async {
  final scope = MatScope();
  try {
    final source = scope.add(await cv.imreadAsync(originalPath));
    if (source.isEmpty) {
      throw StateError('Source image could not be decoded for cropping');
    }
    final clamped = corners.clampTo(source.cols, source.rows);

    cv.Mat page;
    if (_isFullImage(clamped, source.cols, source.rows)) {
      if (source.cols < 64 || source.rows < 64) {
        throw StateError(
          'Image is too small (${source.cols} × ${source.rows})',
        );
      }
      page = source;
    } else {
      final (w, h) = clamped.outputSize;
      if (w < 64 || h < 64) {
        throw StateError('Crop area is too small ($w × $h)');
      }

      final src = cv.VecPoint2f.fromList([
        for (final p in clamped.points) cv.Point2f(p.x, p.y),
      ]);
      final dst = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(w - 1.0, 0),
        cv.Point2f(w - 1.0, h - 1.0),
        cv.Point2f(0, h - 1.0),
      ]);
      cv.Mat matrix;
      try {
        matrix = scope.add(await cv.getPerspectiveTransform2fAsync(src, dst));
      } finally {
        src.dispose();
        dst.dispose();
      }
      page = scope.add(
        await cv.warpPerspectiveAsync(
          source,
          matrix,
          (w, h),
          flags: cv.INTER_CUBIC,
          borderMode: cv.BORDER_REPLICATE,
        ),
      );
      scope.release(matrix);
      scope.release(source);
    }

    if (turns != 0) {
      final code = [
        cv.ROTATE_90_CLOCKWISE,
        cv.ROTATE_180,
        cv.ROTATE_90_COUNTERCLOCKWISE,
      ][turns - 1];
      final rotated = scope.add(await cv.rotateAsync(page, code));
      scope.release(page);
      page = rotated;
    }

    final scaled = scope.add(await downscaleTo(page, maxLongEdge));
    scope.release(page);
    page = scaled;

    final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, jpegQuality]);
    final bool ok;
    final List<int> bytes;
    try {
      final encoded = await cv.imencodeAsync('.jpg', page, params: params);
      ok = encoded.$1;
      bytes = encoded.$2;
    } finally {
      params.dispose();
    }
    if (!ok) throw StateError('Cropped image could not be encoded');
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
    return (width: page.cols, height: page.rows);
  } finally {
    scope.dispose();
  }
}
