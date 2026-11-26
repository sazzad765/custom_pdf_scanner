import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/scanner_ui_config.dart';
import 'camera_boundary_overlay.dart';

/// Embeddable interactive 4-corner perspective crop editor widget.
///
/// Displays [imagePath] at its exact aspect ratio (`imageWidth / imageHeight`)
/// and lets the user drag each normalized `[0..1, 0..1]` corner handle.
class CropQuadEditor extends StatefulWidget {
  /// Creates a [CropQuadEditor].
  const CropQuadEditor({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.normalizedCorners,
    required this.onChanged,
    this.quarterTurns = 0,
    this.theme = const ScannerThemeData(),
    super.key,
  });

  /// Path to the original uncropped source image.
  final String imagePath;

  /// Pixel width of [imagePath].
  final int imageWidth;

  /// Pixel height of [imagePath].
  final int imageHeight;

  /// Four clockwise corners normalized to `[0..1, 0..1]` of the unrotated image.
  final List<Offset> normalizedCorners;

  /// Callback invoked whenever a corner handle is dragged.
  final ValueChanged<List<Offset>> onChanged;

  /// Visual clockwise 90° quarter-turn preview rotation (`0..3`).
  final int quarterTurns;

  /// Visual styling tokens.
  final ScannerThemeData theme;

  @override
  State<CropQuadEditor> createState() => _CropQuadEditorState();
}

class _CropQuadEditorState extends State<CropQuadEditor> {
  int? _activeHandle;

  static const _handleSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final safeW = math.max(1, widget.imageWidth).toDouble();
    final safeH = math.max(1, widget.imageHeight).toDouble();

    return RotatedBox(
      quarterTurns: widget.quarterTurns % 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 440.0;
          final scale = math.min(maxW / safeW, maxH / safeH);
          final dispW = safeW * scale;
          final dispH = safeH * scale;

          return Center(
            child: SizedBox(
              width: dispW,
              height: dispH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CameraBoundaryOverlay(
                        corners: widget.normalizedCorners,
                        color: widget.theme.cropFrameColor,
                        strokeWidth: 2.5,
                        outsideMaskColor: widget.theme.cropOutsideMaskColor,
                      ),
                    ),
                  ),
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      left:
                          widget.normalizedCorners[i].dx * dispW -
                          _handleSize / 2,
                      top:
                          widget.normalizedCorners[i].dy * dispH -
                          _handleSize / 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => setState(() => _activeHandle = i),
                        onPanEnd: (_) => setState(() => _activeHandle = null),
                        onPanCancel: () => setState(() => _activeHandle = null),
                        onPanUpdate: (details) {
                          final updated = [...widget.normalizedCorners];
                          final next =
                              updated[i] +
                              Offset(
                                details.delta.dx / dispW,
                                details.delta.dy / dispH,
                              );
                          updated[i] = Offset(
                            next.dx.clamp(0.0, 1.0),
                            next.dy.clamp(0.0, 1.0),
                          );
                          widget.onChanged(updated);
                        },
                        child: SizedBox.square(
                          dimension: _handleSize,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: _activeHandle == i ? 26 : 20,
                              height: _activeHandle == i ? 26 : 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.theme.cropFrameColor,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
