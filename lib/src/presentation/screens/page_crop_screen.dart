import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controller/custom_scanner_controller.dart';
import '../../domain/crop_corners.dart';
import '../../domain/crop_models.dart';
import '../../domain/scanned_page.dart';
import '../../domain/scanner_failure.dart';
import '../widgets/crop_quad_editor.dart';

/// Full-screen interactive 4-corner perspective crop and rotation screen.
class PageCropScreen extends StatefulWidget {
  /// Creates a [PageCropScreen].
  const PageCropScreen({
    required this.controller,
    required this.pageId,
    super.key,
  });

  /// Active scanner controller.
  final CustomScannerController controller;

  /// ID of the page to crop.
  final String pageId;

  @override
  State<PageCropScreen> createState() => _PageCropScreenState();
}

class _PageCropScreenState extends State<PageCropScreen> {
  late List<Offset> _normalizedCorners;
  late int _quarterTurns;
  late int _origW;
  late int _origH;
  bool _saving = false;
  String? _error;

  ScannedPage? get _page => widget.controller.pageById(widget.pageId);

  @override
  void initState() {
    super.initState();
    final p = _page!;
    _origW = math.max(1, p.originalWidth);
    _origH = math.max(1, p.originalHeight);
    _quarterTurns = p.rotationQuarterTurns;
    final initial = p.corners ?? CropCorners.full(_origW, _origH);
    _normalizedCorners = [
      for (final pt in initial.points) Offset(pt.x / _origW, pt.y / _origH),
    ];
  }

  CropCorners _toPixelCorners() => CropCorners(
    topLeft: PagePoint(
      _normalizedCorners[0].dx * _origW,
      _normalizedCorners[0].dy * _origH,
    ),
    topRight: PagePoint(
      _normalizedCorners[1].dx * _origW,
      _normalizedCorners[1].dy * _origH,
    ),
    bottomRight: PagePoint(
      _normalizedCorners[2].dx * _origW,
      _normalizedCorners[2].dy * _origH,
    ),
    bottomLeft: PagePoint(
      _normalizedCorners[3].dx * _origW,
      _normalizedCorners[3].dy * _origH,
    ),
  );

  Future<void> _autoDetect() async {
    setState(() => _error = null);
    try {
      final res = await widget.controller.detectCornersForPage(widget.pageId);
      if (!mounted) return;
      if (res.corners != null) {
        final padded = res.corners!.withMargin(
          widget.controller.config.processing.cropSafetyMargin,
          _origW,
          _origH,
        );
        setState(() {
          _normalizedCorners = [
            for (final pt in padded.points)
              Offset(pt.x / _origW, pt.y / _origH),
          ];
        });
      } else {
        setState(() => _error = 'Could not detect clear page edges.');
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _resetFull() {
    setState(() {
      _error = null;
      _normalizedCorners = const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ];
    });
  }

  Future<void> _apply() async {
    final corners = _toPixelCorners();
    if (!corners.isConvex || corners.minAngle < 25) {
      setState(
        () => _error = 'Keep all four corners uncrossed to form a valid page.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updatePageCrop(
        widget.pageId,
        corners: corners,
        rotationQuarterTurns: _quarterTurns,
        cropSource: CropSource.manual,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ScannerFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final uiCfg = widget.controller.config.ui;
    final theme = uiCfg.theme;
    final strings = uiCfg.strings;

    if (page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(strings.cropPageTitle),
        actions: [
          IconButton(
            tooltip: 'Auto-detect edges',
            onPressed: _saving ? null : _autoDetect,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          TextButton(
            onPressed: _saving ? null : _resetFull,
            child: Text(
              strings.resetFullImageButton,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                color: theme.dangerColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CropQuadEditor(
                  imagePath: page.originalPath,
                  imageWidth: _origW,
                  imageHeight: _origH,
                  normalizedCorners: _normalizedCorners,
                  quarterTurns: _quarterTurns,
                  theme: theme,
                  onChanged: (next) => setState(() {
                    _normalizedCorners = next;
                    _error = null;
                  }),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _quarterTurns = (_quarterTurns + 1) % 4,
                          ),
                    icon: Icon(uiCfg.icons.rotate, size: 18),
                    label: Text(strings.rotateButton),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: theme.onPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _saving ? null : _apply,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(strings.applyCropButton),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
