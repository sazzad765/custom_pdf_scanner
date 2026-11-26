import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../config/capture_config.dart';
import '../../domain/scanner_failure.dart';
import '../crop/document_detector.dart';
import 'camera_stream_service.dart';

/// Cross-platform (`Android` CameraX + `iOS` AVFoundation) implementation of
/// [CameraStreamService] backed by Flutter's `camera` plugin.
class FlutterCameraStreamService implements CameraStreamService {
  /// Creates a [FlutterCameraStreamService].
  FlutterCameraStreamService({
    this.analysisEdge = 480,
    this.resolution = ScannerCameraResolution.max,
  });

  /// Maximum long edge of subsampled preview frames passed to OpenCV.
  final int analysisEdge;

  /// Sensor capture resolution preset.
  final ScannerCameraResolution resolution;

  CameraController? _controller;
  CameraDescription? _camera;
  bool _streaming = false;
  bool _busy = false;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  @override
  double get previewAspectRatio {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 3 / 4;
    return 1 / c.value.aspectRatio;
  }

  ResolutionPreset get _preset => switch (resolution) {
    ScannerCameraResolution.medium => ResolutionPreset.medium,
    ScannerCameraResolution.high => ResolutionPreset.high,
    ScannerCameraResolution.veryHigh => ResolutionPreset.veryHigh,
    ScannerCameraResolution.ultraHigh => ResolutionPreset.ultraHigh,
    ScannerCameraResolution.max => ResolutionPreset.max,
  };

  @override
  Future<void> open() async {
    if (isOpen) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const CameraUnavailableException(
          'No camera was found on this device.',
        );
      }
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _camera!,
        _preset,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;
      await _safely(() => controller.setFocusMode(FocusMode.auto));
      await _safely(() => controller.setExposureMode(ExposureMode.auto));
      await _safely(() => controller.setFlashMode(FlashMode.off));
    } on CameraException catch (e) {
      await _dispose();
      final code = e.code.toLowerCase();
      if (code.contains('accessdenied') ||
          code.contains('restricted') ||
          code.contains('permission')) {
        throw const CameraPermissionDeniedException();
      }
      throw CameraUnavailableException(e.description, e);
    }
  }

  Future<void> _safely(Future<void> Function() fn) async {
    try {
      await fn();
    } on Object {
      // Optional hardware feature unsupported on some devices.
    }
  }

  @override
  Future<void> close() => _dispose();

  Future<void> _dispose() async {
    final c = _controller;
    _controller = null;
    _streaming = false;
    if (c != null) await c.dispose();
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  @override
  Future<void> setTorch(bool enabled) async {
    final c = _controller;
    if (c == null) return;
    await _safely(
      () => c.setFlashMode(enabled ? FlashMode.torch : FlashMode.off),
    );
  }

  @override
  Future<String> captureStill() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw const CameraUnavailableException();
    }
    try {
      final file = await c.takePicture();
      return file.path;
    } on CameraException catch (e) {
      throw CaptureFailedException(e);
    }
  }

  @override
  Future<void> startFrames(
    Future<void> Function(LumaFrame frame) onFrame,
  ) async {
    final c = _controller;
    if (c == null || _streaming) return;
    _streaming = true;
    await c.startImageStream((image) async {
      if (_busy || !_streaming) return;
      _busy = true;
      try {
        await onFrame(_reduceToLuma(image));
      } on Object {
        // Ignore transient frame errors.
      } finally {
        _busy = false;
      }
    });
  }

  LumaFrame _reduceToLuma(CameraImage image) {
    final long = image.width > image.height ? image.width : image.height;
    final step = (long / analysisEdge).ceil().clamp(1, 16);
    final w = image.width ~/ step;
    final h = image.height ~/ step;
    final out = Uint8List(w * h);

    if (image.format.group == ImageFormatGroup.bgra8888 ||
        image.planes.length == 1 &&
            image.planes.first.bytesPerRow >= image.width * 4) {
      // iOS BGRA8888 plane -> fast integer BT.601 luma approximation.
      final plane = image.planes.first;
      final src = plane.bytes;
      final stride = plane.bytesPerRow;
      for (var y = 0; y < h; y++) {
        final row = y * step * stride;
        final o = y * w;
        for (var x = 0; x < w; x++) {
          final px = row + x * step * 4;
          if (px + 2 < src.length) {
            final b = src[px];
            final g = src[px + 1];
            final r = src[px + 2];
            out[o + x] = (29 * b + 150 * g + 77 * r) >> 8;
          }
        }
      }
      return LumaFrame(
        bytes: out,
        width: w,
        height: h,
        rotationDegrees: Platform.isIOS
            ? 0
            : (_camera?.sensorOrientation ?? 90),
      );
    }

    // Android YUV420 Y-plane.
    final plane = image.planes.first;
    final src = plane.bytes;
    final stride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;
    for (var y = 0; y < h; y++) {
      final row = y * step * stride;
      final o = y * w;
      for (var x = 0; x < w; x++) {
        final idx = row + x * step * pixelStride;
        if (idx < src.length) out[o + x] = src[idx];
      }
    }
    return LumaFrame(
      bytes: out,
      width: w,
      height: h,
      rotationDegrees: _camera?.sensorOrientation ?? 90,
    );
  }

  @override
  Future<void> stopFrames() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } on Object {
      // Stream already stopped.
    }
  }
}
