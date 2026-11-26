import '../../domain/crop_corners.dart';

/// Pixel dimensions written by a perspective crop.
typedef CropOutput = ({int width, int height});

/// Interface for warping a 4-corner quadrilateral into a flat, upright page image.
abstract interface class PerspectiveCropper {
  /// Warps [corners] of [originalPath] into an upright rectangle, applies
  /// [quarterTurns] clockwise rotations, caps the long edge at [maxLongEdge],
  /// and writes a JPEG to [outputPath].
  Future<CropOutput> crop({
    required String originalPath,
    required CropCorners corners,
    required int quarterTurns,
    required String outputPath,
    required int maxLongEdge,
    required int jpegQuality,
  });

  /// Returns oriented `(width, height)` of [path] in pixels.
  Future<(int width, int height)> imageSize(String path);
}
