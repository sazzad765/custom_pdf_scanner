import 'dart:typed_data';

import '../../domain/crop_models.dart';

/// Reduced 8-bit luma frame extracted from a live camera preview stream.
class LumaFrame {
  /// Creates a [LumaFrame].
  const LumaFrame({
    required this.bytes,
    required this.width,
    required this.height,
    this.rotationDegrees = 0,
  });

  /// Tightly packed 8-bit grayscale luma buffer (`width * height` bytes).
  final Uint8List bytes;

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Clockwise rotation in degrees required to orient the frame upright.
  final int rotationDegrees;
}

/// Interface for detecting four document corners in still images or camera frames.
abstract interface class DocumentDetector {
  /// Detects document corners on a reduced decode of [imagePath], returning
  /// coordinates in the full oriented image space.
  Future<DetectionResult> detectFile(String imagePath);

  /// Detects document corners on a live camera [frame], returning coordinates
  /// in the upright frame pixel space.
  Future<DetectionResult> detectFrame(LumaFrame frame);
}
