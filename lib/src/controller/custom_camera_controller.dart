import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/capture_config.dart';
import '../domain/crop_corners.dart';
import '../domain/scanner_failure.dart';
import '../infrastructure/camera/camera_stream_service.dart';
import '../infrastructure/crop/document_detector.dart';

/// Lifecycle state of the built-in camera controller.
enum CameraLifecycleStatus {
  /// Camera is not open.
  closed,

  /// Camera hardware is initializing.
  opening,

  /// Preview is active and ready to capture.
  ready,

  /// Camera failed to open (see `failure`).
  failed,
}

/// Live OpenCV boundary tracking state on the camera preview.
enum LiveBoundaryPhase {
  /// Looking for a document quad.
  searching,

  /// Document quad detected; waiting for hand stability.
  detected,

  /// Document quad has held steady for `autoCaptureStableFrames`.
  stable,
}

/// Manages camera lifecycle, torch, live OpenCV boundary overlay, and
/// auto/manual shutter for both single-page and multi-shot camera capture.
class CustomCameraController extends ChangeNotifier
    with WidgetsBindingObserver {
  /// Creates a [CustomCameraController].
  CustomCameraController({
    required CameraStreamService camera,
    required DocumentDetector detector,
    this.config = const CaptureConfig(),
  }) : _camera = camera,
       _detector = detector,
       _torch = config.initialTorchOn,
       _autoCapture = config.autoCaptureOnStableEdge;

  final CameraStreamService _camera;
  final DocumentDetector _detector;

  /// Capture settings driving analysis interval, stability frames, and torch.
  final CaptureConfig config;

  CameraLifecycleStatus _status = CameraLifecycleStatus.closed;
  ScannerFailure? _failure;
  bool _torch;
  bool _autoCapture;
  bool _capturing = false;
  bool _wantOpen = false;
  LiveBoundaryPhase _phase = LiveBoundaryPhase.searching;
  List<PagePoint>? _boundary;
  bool _lowLight = false;
  int _stableCount = 0;
  List<PagePoint>? _lastCapturedBoundary;
  bool _armed = true;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  /// Callback invoked when [autoCaptureEnabled] triggers a steady-page capture.
  VoidCallback? onAutoCaptureTriggered;

  /// Current camera initialization state.
  CameraLifecycleStatus get status => _status;

  /// Error if [status] is [CameraLifecycleStatus.failed].
  ScannerFailure? get failure => _failure;

  /// Whether the flashlight/torch is turned on.
  bool get torchEnabled => _torch;

  /// Whether steady-edge auto-capture is enabled.
  bool get autoCaptureEnabled => _autoCapture;

  /// True while a full-resolution photo is being captured.
  bool get isCapturing => _capturing;

  /// Current boundary detection phase.
  LiveBoundaryPhase get boundaryPhase => _phase;

  /// True when scene luminance is below [CaptureConfig.lowLightThreshold].
  bool get isLowLight => _lowLight;

  /// Detected document corners normalized to `[0..1, 0..1]` of the upright preview.
  List<PagePoint>? get normalizedBoundary => _boundary;

  /// Upright preview aspect ratio (`width / height`).
  double get previewAspectRatio => _camera.previewAspectRatio;

  /// Builds the live camera preview widget.
  Widget buildPreview() => _camera.buildPreview();

  /// Opens the camera and starts live frame boundary detection.
  Future<void> open() async {
    _wantOpen = true;
    WidgetsBinding.instance.addObserver(this);
    await _openInternal();
  }

  Future<void> _openInternal() async {
    if (_status == CameraLifecycleStatus.opening ||
        _status == CameraLifecycleStatus.ready) {
      return;
    }
    _update(() {
      _status = CameraLifecycleStatus.opening;
      _failure = null;
    });
    try {
      await _camera.open();
      if (!_wantOpen) {
        await _camera.close();
        return;
      }
      if (_torch && config.enableTorch) {
        await _camera.setTorch(true);
      }
      _update(() => _status = CameraLifecycleStatus.ready);
      await _camera.startFrames(_analyseFrame);
    } on ScannerFailure catch (f) {
      _update(() {
        _status = CameraLifecycleStatus.failed;
        _failure = f;
      });
    } on Object catch (e) {
      _update(() {
        _status = CameraLifecycleStatus.failed;
        _failure = CameraUnavailableException(null, e);
      });
    }
  }

  /// Stops frame streaming and closes the camera.
  Future<void> close() async {
    _wantOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    await _releaseInternal();
  }

  Future<void> _releaseInternal() async {
    await _camera.stopFrames();
    await _camera.close();
    _update(() {
      _status = CameraLifecycleStatus.closed;
      _boundary = null;
      _phase = LiveBoundaryPhase.searching;
      _stableCount = 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_wantOpen) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_releaseInternal());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_openInternal());
    }
  }

  /// Retries opening the camera after a failure.
  Future<void> retry() => _openInternal();

  /// Toggles the camera torch on or off.
  Future<void> toggleTorch() async {
    if (!config.enableTorch) return;
    _update(() => _torch = !_torch);
    if (_status == CameraLifecycleStatus.ready) {
      await _camera.setTorch(_torch);
    }
  }

  /// Toggles automatic capture on steady document edges.
  void toggleAutoCapture() => _update(() {
    _autoCapture = !_autoCapture;
    _stableCount = 0;
  });

  /// Captures a still image and disarms auto-capture until the sheet moves.
  Future<String> takePhoto() async {
    if (_capturing) throw const CaptureFailedException('Capture in progress');
    if (_status != CameraLifecycleStatus.ready) {
      throw const CameraUnavailableException();
    }
    _update(() => _capturing = true);
    try {
      final path = await _camera.captureStill();
      _lastCapturedBoundary = _boundary;
      _armed = false;
      _stableCount = 0;
      return path;
    } finally {
      _update(() => _capturing = false);
    }
  }

  Future<void> _analyseFrame(LumaFrame frame) async {
    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < config.analysisInterval || _capturing) {
      return;
    }
    _lastAnalysis = now;

    var sum = 0;
    var samples = 0;
    for (var i = 0; i < frame.bytes.length; i += 7) {
      sum += frame.bytes[i];
      samples++;
    }
    final luma = samples == 0 ? 128.0 : sum / samples;

    final result = await _detector.detectFrame(frame);
    final upright = frame.rotationDegrees % 180 == 0;
    final w = (upright ? frame.width : frame.height).toDouble();
    final h = (upright ? frame.height : frame.width).toDouble();
    final corners = result.corners?.points
        .map((p) => PagePoint(p.x / w, p.y / h))
        .toList();

    final prev = _boundary;
    final still =
        corners != null &&
        prev != null &&
        _maxShift(corners, prev) < config.autoCaptureTolerance;
    _stableCount = corners == null ? 0 : (still ? _stableCount + 1 : 0);

    if (!_armed) {
      final last = _lastCapturedBoundary;
      if (corners == null || last == null || _maxShift(corners, last) > 0.08) {
        _armed = true;
      }
    }

    _update(() {
      _lowLight = luma < config.lowLightThreshold;
      _boundary = corners;
      _phase = corners == null || !result.isConfident
          ? LiveBoundaryPhase.searching
          : _stableCount >= config.autoCaptureStableFrames
          ? LiveBoundaryPhase.stable
          : LiveBoundaryPhase.detected;
    });

    if (_autoCapture &&
        _armed &&
        _phase == LiveBoundaryPhase.stable &&
        !_lowLight &&
        !_capturing) {
      _stableCount = 0;
      onAutoCaptureTriggered?.call();
    }
  }

  static double _maxShift(List<PagePoint> a, List<PagePoint> b) {
    var maxDist = 0.0;
    for (var i = 0; i < 4; i++) {
      final d = a[i].distanceTo(b[i]);
      if (d > maxDist) maxDist = d;
    }
    return maxDist;
  }

  void _update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  @override
  void dispose() {
    _wantOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera.stopFrames().then((_) => _camera.close()));
    super.dispose();
  }
}
