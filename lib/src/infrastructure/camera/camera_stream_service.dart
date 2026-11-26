import 'package:flutter/widgets.dart';

import '../crop/document_detector.dart';

/// Cross-platform camera preview & still-capture contract used by
/// `CustomCameraController` on both Android and iOS.
abstract interface class CameraStreamService {
  /// Opens the back camera.
  Future<void> open();

  /// Releases camera resources.
  Future<void> close();

  /// Whether the camera is currently initialized.
  bool get isOpen;

  /// Upright preview aspect ratio (`width / height`).
  double get previewAspectRatio;

  /// Builds the live camera preview widget.
  Widget buildPreview();

  /// Enables or disables the torch/flashlight.
  Future<void> setTorch(bool enabled);

  /// Captures a high-resolution JPEG still and returns its temporary file path.
  Future<String> captureStill();

  /// Starts streaming reduced 8-bit luma frames for live OpenCV edge detection.
  Future<void> startFrames(Future<void> Function(LumaFrame frame) onFrame);

  /// Stops streaming preview frames.
  Future<void> stopFrames();
}
