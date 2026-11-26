import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/capture_config.dart';
import '../../config/custom_scanner_config.dart';
import '../../config/scanner_ui_config.dart';
import '../../controller/custom_camera_controller.dart';
import '../../infrastructure/camera/camera_stream_service.dart';
import '../../infrastructure/camera/flutter_camera_stream_service.dart';
import '../../infrastructure/camera/page_capture_service.dart';
import '../../infrastructure/crop/document_detector.dart';
import '../../infrastructure/crop/opencv_document_detector.dart';
import '../widgets/camera_boundary_overlay.dart';

/// Built-in cross-platform (`Android` & `iOS`) camera capture screen supporting
/// both **Single-Page** (`maxShots == 1`) and **Multi-Page** (`maxShots > 1`)
/// capture with live OpenCV boundary tracking, torch control, and auto-shutter.
///
/// Pops with `List<CapturedRawPage>` (empty if cancelled).
class MultiShotCameraScreen extends StatefulWidget {
  /// Creates a [MultiShotCameraScreen].
  const MultiShotCameraScreen({
    required this.config,
    required this.scanMode,
    this.maxShots,
    this.cameraServiceOverride,
    this.detectorOverride,
    super.key,
  });

  /// Full scanner configuration.
  final CustomScannerConfig config;

  /// Whether this camera session captures a single shot or a multi-page batch.
  final ScanMode scanMode;

  /// Optional cap on how many shots can be captured in this camera visit.
  final int? maxShots;

  /// Optional test double for [CameraStreamService].
  final CameraStreamService? cameraServiceOverride;

  /// Optional test double for [DocumentDetector].
  final DocumentDetector? detectorOverride;

  @override
  State<MultiShotCameraScreen> createState() => _MultiShotCameraScreenState();
}

class _MultiShotCameraScreenState extends State<MultiShotCameraScreen> {
  late final CustomCameraController _camera;
  final List<CapturedRawPage> _captured = <CapturedRawPage>[];

  int? get _effectiveLimit => widget.scanMode == ScanMode.singlePage
      ? 1
      : widget.maxShots ?? widget.config.capture.maxPages;

  bool get _atLimit =>
      _effectiveLimit != null && _captured.length >= _effectiveLimit!;

  @override
  void initState() {
    super.initState();
    _camera = CustomCameraController(
      camera:
          widget.cameraServiceOverride ??
          FlutterCameraStreamService(
            analysisEdge: widget.config.capture.previewAnalysisEdge,
            resolution: widget.config.capture.cameraResolution,
          ),
      detector:
          widget.detectorOverride ??
          OpenCvDocumentDetector(config: widget.config.processing),
      config: widget.config.capture,
    );
    _camera.onAutoCaptureTriggered = () => unawaited(_shoot());
    _camera.addListener(_onCameraChanged);
    unawaited(_camera.open());
  }

  @override
  void dispose() {
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    if (_camera.isCapturing || _atLimit) return;
    try {
      final path = await _camera.takePhoto();
      if (!mounted) return;
      setState(() {
        _captured.add(CapturedRawPage(path: path, preCropped: false));
      });
      if (widget.scanMode == ScanMode.singlePage || _atLimit) {
        await _finish();
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _finish() async {
    await _camera.close();
    if (mounted) {
      Navigator.of(context).pop(List<CapturedRawPage>.unmodifiable(_captured));
    }
  }

  Future<void> _cancel() async {
    await _camera.close();
    if (mounted) {
      Navigator.of(context).pop(const <CapturedRawPage>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.config.ui;
    final theme = ui.theme;
    final strings = ui.strings;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(strings.cameraScreenTitle),
        actions: [
          TextButton.icon(
            onPressed: _camera.toggleAutoCapture,
            icon: Icon(
              _camera.autoCaptureEnabled
                  ? Icons.motion_photos_auto_rounded
                  : Icons.touch_app_outlined,
              color: _camera.autoCaptureEnabled
                  ? theme.cropFrameColor
                  : Colors.white70,
              size: 20,
            ),
            label: Text(
              _camera.autoCaptureEnabled ? 'Auto' : 'Manual',
              style: TextStyle(
                color: _camera.autoCaptureEnabled
                    ? theme.cropFrameColor
                    : Colors.white70,
              ),
            ),
          ),
          if (widget.config.capture.enableTorch)
            IconButton(
              onPressed: _camera.toggleTorch,
              icon: Icon(
                _camera.torchEnabled ? ui.icons.torchOn : ui.icons.torchOff,
                color: _camera.torchEnabled ? Colors.amber : Colors.white,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildViewport(theme)),
            _buildBottomControls(theme, strings),
          ],
        ),
      ),
    );
  }

  Widget _buildViewport(ScannerThemeData theme) {
    if (_camera.status == CameraLifecycleStatus.opening ||
        _camera.status == CameraLifecycleStatus.closed) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_camera.status == CameraLifecycleStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _camera.failure?.message ?? 'Camera unavailable',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _camera.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final boundary = _camera.normalizedBoundary;
    final phaseColor = switch (_camera.boundaryPhase) {
      LiveBoundaryPhase.stable => theme.successColor,
      LiveBoundaryPhase.detected => theme.cropFrameColor,
      LiveBoundaryPhase.searching => Colors.white54,
    };

    return Center(
      child: AspectRatio(
        aspectRatio: _camera.previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _camera.buildPreview(),
            if (boundary != null)
              CameraBoundaryOverlay(
                corners: [for (final p in boundary) Offset(p.x, p.y)],
                color: phaseColor,
                strokeWidth: 3.0,
                fillColor: phaseColor.withValues(alpha: 0.14),
              ),
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _camera.isLowLight
                        ? 'Low light — turn on flash or move to brighter light'
                        : switch (_camera.boundaryPhase) {
                            LiveBoundaryPhase.stable => 'Hold steady…',
                            LiveBoundaryPhase.detected =>
                              'Page detected — hold steady',
                            LiveBoundaryPhase.searching =>
                              widget.scanMode == ScanMode.multiPage
                                  ? 'Align page and capture multiple sheets'
                                  : 'Align document inside frame',
                          },
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(ScannerThemeData theme, ScannerStrings strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: latest captured thumbnail + counter in multi-page mode.
          SizedBox(
            width: 88,
            child: _captured.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_captured.last.path),
                          width: 44,
                          height: 56,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_captured.length}',
                          style: TextStyle(
                            color: theme.onPrimaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          // Center: Shutter button.
          GestureDetector(
            onTap: _camera.status == CameraLifecycleStatus.ready && !_atLimit
                ? _shoot
                : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _camera.isCapturing ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ),
          // Right: Done button in multi-page mode once >= 1 page captured.
          SizedBox(
            width: 88,
            child: widget.scanMode == ScanMode.multiPage && _captured.isNotEmpty
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.onPrimaryColor,
                    ),
                    onPressed: _camera.isCapturing ? null : _finish,
                    child: Text(strings.confirmPageButton),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
