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
/// **Single-Page**, **Multi-Page**, and **NID Card** capture (with an ID-1 card
/// target guide overlay, live OpenCV boundary tracking, torch, and auto-shutter).
///
/// Pops with `List<CapturedRawPage>` (empty if cancelled).
class MultiShotCameraScreen extends StatefulWidget {
  /// Creates a [MultiShotCameraScreen].
  const MultiShotCameraScreen({
    required this.config,
    required this.scanMode,
    this.maxShots,
    this.guidePrompt,
    this.idCardFrameAspectRatio,
    this.cameraServiceOverride,
    this.detectorOverride,
    super.key,
  });

  /// Full scanner configuration.
  final CustomScannerConfig config;

  /// Whether this camera session captures a single shot, multi-page batch, or NID card.
  final ScanMode scanMode;

  /// Optional cap on how many shots can be captured in this camera visit.
  final int? maxShots;

  /// Optional custom instruction pill shown at the top of the camera preview
  /// (e.g. `"Align FRONT side of NID card inside frame"`).
  final String? guidePrompt;

  /// When provided (or when [scanMode] is [ScanMode.nidCard]), draws a centered
  /// ID-card framing box with this `width / height` aspect ratio.
  final double? idCardFrameAspectRatio;

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

  int? get _effectiveLimit => switch (widget.scanMode) {
    ScanMode.singlePage => 1,
    ScanMode.nidCard => widget.maxShots ?? widget.config.nid.expectedSideCount,
    ScanMode.multiPage => widget.maxShots ?? widget.config.capture.maxPages,
  };

  bool get _atLimit =>
      _effectiveLimit != null && _captured.length >= _effectiveLimit!;

  double? get _activeIdAspectRatio {
    if (widget.idCardFrameAspectRatio != null) {
      return widget.idCardFrameAspectRatio;
    }
    if (widget.scanMode == ScanMode.nidCard &&
        widget.config.nid.showIdFrameGuideInCamera) {
      return widget.config.nid.isoCardAspectRatio;
    }
    return null;
  }

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
      if (_effectiveLimit == 1 || _atLimit) {
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

  String _resolvePromptText(ScannerStrings strings) {
    if (_camera.isLowLight) {
      return 'Low light — turn on flash or move to brighter light';
    }
    if (_camera.boundaryPhase == LiveBoundaryPhase.stable) {
      return 'Hold steady…';
    }
    if (_camera.boundaryPhase == LiveBoundaryPhase.detected) {
      return 'Card / page detected — hold steady';
    }
    if (widget.guidePrompt != null) {
      return widget.guidePrompt!;
    }
    if (widget.scanMode == ScanMode.nidCard) {
      return _captured.isEmpty
          ? strings.nidCameraFrontHint
          : strings.nidCameraBackHint;
    }
    return widget.scanMode == ScanMode.multiPage
        ? 'Align page and capture multiple sheets'
        : 'Align document inside frame';
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
        title: Text(
          widget.scanMode == ScanMode.nidCard
              ? strings.nidScreenTitle
              : strings.cameraScreenTitle,
        ),
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
            Expanded(child: _buildViewport(theme, strings)),
            _buildBottomControls(theme, strings),
          ],
        ),
      ),
    );
  }

  Widget _buildViewport(ScannerThemeData theme, ScannerStrings strings) {
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
    final idRatio = _activeIdAspectRatio;

    return Center(
      child: AspectRatio(
        aspectRatio: _camera.previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _camera.buildPreview(),
            if (idRatio != null && boundary == null)
              _IdCardFrameGuide(
                cardAspectRatio: idRatio,
                borderColor: theme.cropFrameColor,
              ),
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
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _resolvePromptText(strings),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
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
    final allowPartialFinish =
        widget.scanMode == ScanMode.multiPage && _captured.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
          SizedBox(
            width: 88,
            child: allowPartialFinish
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

class _IdCardFrameGuide extends StatelessWidget {
  const _IdCardFrameGuide({
    required this.cardAspectRatio,
    required this.borderColor,
  });

  final double cardAspectRatio;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _IdCardGuidePainter(
        cardAspectRatio: cardAspectRatio,
        borderColor: borderColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _IdCardGuidePainter extends CustomPainter {
  _IdCardGuidePainter({
    required this.cardAspectRatio,
    required this.borderColor,
  });

  final double cardAspectRatio;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final boxW = size.width * 0.88;
    final boxH = (boxW / cardAspectRatio).clamp(80.0, size.height * 0.65);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: boxW,
      height: boxH,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(mask, Paint()..color = const Color(0x88000000));

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_IdCardGuidePainter oldDelegate) =>
      oldDelegate.cardAspectRatio != cardAspectRatio ||
      oldDelegate.borderColor != borderColor;
}
