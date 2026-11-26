import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/capture_config.dart';
import '../../config/nid_scan_config.dart';
import '../../config/scanner_ui_config.dart';
import '../../controller/custom_scanner_controller.dart';
import '../../domain/page_quality.dart';
import '../../domain/scan_filter.dart';
import '../../domain/scanned_page.dart';
import '../../domain/scanned_pdf_result.dart';
import '../../infrastructure/camera/page_capture_service.dart';
import 'multi_shot_camera_screen.dart';
import 'page_crop_screen.dart';
import 'page_editor_screen.dart';

/// Dedicated guided **National ID / Smart ID / Driver's License** scan screen
/// (`ScanMode.nidCard`).
///
/// Provides structured **Front Side** and **Back Side** card slots, inline
/// crop/rotate/filter/retake actions, one-tap Front ⇅ Back swap, interactive
/// PDF layout selection (`1 Page Top & Bottom`, `1 Page Side-by-Side`, or
/// `2 Separate Pages`), print size presets (`Readable`, `1:1 ISO ID-1`, `Large`),
/// and local PDF export.
class NidScanScreen extends StatefulWidget {
  /// Creates a [NidScanScreen].
  const NidScanScreen({
    required this.controller,
    this.autoLaunchCaptureOnOpen = true,
    this.disposeControllerOnExit = false,
    super.key,
  });

  /// Scanner controller owning the Front (`pages[0]`) and Back (`pages[1]`) slots.
  final CustomScannerController controller;

  /// Automatically launches Front (and Back when `autoAdvanceToBackCapture` is true)
  /// capture when opened with 0 pages.
  final bool autoLaunchCaptureOnOpen;

  /// Disposes [controller] when this screen exits.
  final bool disposeControllerOnExit;

  @override
  State<NidScanScreen> createState() => _NidScanScreenState();
}

class _NidScanScreenState extends State<NidScanScreen> {
  late NidPdfLayout _selectedLayout;
  late NidCardPrintSize _selectedPrintSize;
  bool _exiting = false;

  CustomScannerController get _ctrl => widget.controller;

  ScannedPage? get _frontPage => _ctrl.pages.isNotEmpty ? _ctrl.pages[0] : null;
  ScannedPage? get _backPage => _ctrl.pages.length > 1 ? _ctrl.pages[1] : null;

  bool get _needsBack => _ctrl.config.nid.sides == NidScanSides.frontAndBack;

  bool get _isReadyToExport =>
      _frontPage != null && (!_needsBack || _backPage != null);

  @override
  void initState() {
    super.initState();
    _selectedLayout = _ctrl.config.nid.pdfLayout;
    _selectedPrintSize = _ctrl.config.nid.cardPrintSize;
    _ctrl.addListener(_onChanged);

    if (widget.autoLaunchCaptureOnOpen && _ctrl.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runInitialGuidedCapture());
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    if (widget.disposeControllerOnExit) {
      unawaited(_ctrl.disposeWorkspaceAndController());
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runInitialGuidedCapture() async {
    final gotFront = await _captureSlot(isFront: true);
    if (!mounted || !gotFront) {
      if (_ctrl.isEmpty) await _popCancel(skipConfirm: true);
      return;
    }
    if (_needsBack &&
        _backPage == null &&
        _ctrl.config.nid.autoAdvanceToBackCapture) {
      await _captureSlot(isFront: false);
    }
  }

  Future<bool> _captureSlot({required bool isFront}) async {
    if (_ctrl.isBusy) return false;
    final existingPage = isFront ? _frontPage : _backPage;
    final strings = _ctrl.config.ui.strings;

    try {
      List<ScannedPage> added;
      if (_ctrl.shouldUseNativeMlKit()) {
        // When starting empty on Android ML Kit with autoAdvance, allow scanning
        // up to 2 sides in one native session, or 1 side when retaking/filling a single slot.
        final limit =
            (isFront &&
                existingPage == null &&
                _needsBack &&
                _backPage == null &&
                _ctrl.config.nid.autoAdvanceToBackCapture)
            ? 2
            : 1;
        added = await _ctrl.captureAndProcessWithMlKit(
          modeOverride: ScanMode.nidCard,
          explicitPageLimit: limit,
          replacePageId: existingPage?.id,
          insertAt: existingPage == null && isFront ? 0 : null,
        );
      } else {
        if (!mounted) return false;
        final raw = await Navigator.of(context).push<List<CapturedRawPage>>(
          MaterialPageRoute(
            builder: (_) => MultiShotCameraScreen(
              config: _ctrl.config,
              scanMode: ScanMode.nidCard,
              maxShots: 1,
              guidePrompt: isFront
                  ? strings.nidCameraFrontHint
                  : strings.nidCameraBackHint,
            ),
          ),
        );
        if (!mounted || raw == null || raw.isEmpty) return false;
        added = await _ctrl.addCapturedPages(
          raw,
          replacePageId: existingPage?.id,
          insertAt: existingPage == null && isFront ? 0 : null,
        );
      }
      return added.isNotEmpty;
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
      return false;
    }
  }

  Future<void> _openEditorFor(ScannedPage page, {required bool isFront}) async {
    if (_ctrl.isBusy) return;
    final outcome = await Navigator.of(context).push<PageEditorOutcome>(
      MaterialPageRoute(
        builder: (_) => PageEditorScreen(
          controller: _ctrl,
          pageId: page.id,
          allowDelete: !isFront || _backPage == null,
        ),
      ),
    );
    if (!mounted) return;
    if (outcome == PageEditorOutcome.retake) {
      await _captureSlot(isFront: isFront);
    }
  }

  Future<void> _openCropFor(ScannedPage page) async {
    if (_ctrl.isBusy) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PageCropScreen(controller: _ctrl, pageId: page.id),
      ),
    );
  }

  Future<void> _showBatchFilterSheet() async {
    if (_ctrl.isEmpty || _ctrl.isBusy) return;
    final ui = _ctrl.config.ui;
    final filters = _ctrl.config.processing.availableFilters;
    final chosen = await showModalBottomSheet<ScanFilter>(
      context: context,
      backgroundColor: ui.theme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ui.theme.borderRadius),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                ui.strings.applyFilterToAllButton,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ui.theme.textColor,
                ),
              ),
            ),
            for (final f in filters)
              ListTile(
                leading: Icon(ui.icons.filter, color: ui.theme.primaryColor),
                title: Text(
                  ui.strings.labelForFilter(f),
                  style: TextStyle(color: ui.theme.textColor),
                ),
                onTap: () => Navigator.of(ctx).pop(f),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      await _ctrl.applyFilterToAll(chosen);
    }
  }

  Future<void> _exportNidPdf() async {
    if (!_isReadyToExport || _ctrl.isBusy) return;
    try {
      final activeNid = _ctrl.config.nid.copyWith(
        pdfLayout: _selectedLayout,
        cardPrintSize: _selectedPrintSize,
      );
      final ScannedPdfResult result = await _ctrl.generatePdf(
        overrideNidConfig: activeNid,
      );
      if (!mounted) return;
      _exiting = true;
      Navigator.of(context).pop(result);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _popCancel({bool skipConfirm = false}) async {
    if (_exiting) return;
    if (!skipConfirm &&
        !_ctrl.isEmpty &&
        _ctrl.config.pageList.confirmBeforeDiscardAll) {
      final ui = _ctrl.config.ui;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ui.strings.discardDialogTitle),
          content: Text(ui.strings.discardDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ui.strings.cancelLabel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ui.theme.dangerColor,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ui.strings.discardConfirmLabel),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    _exiting = true;
    if (widget.disposeControllerOnExit) {
      await _ctrl.clearAll();
    }
    if (mounted) Navigator.of(context).pop<ScannedPdfResult?>(null);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _ctrl.config;
    final nidCfg = cfg.nid;
    final ui = cfg.ui;
    final theme = ui.theme;
    final strings = ui.strings;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ctrl.isBusy) {
          unawaited(_popCancel());
        }
      },
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: AppBar(
          backgroundColor: theme.surfaceColor,
          foregroundColor: theme.textColor,
          elevation: 0,
          leading: IconButton(
            onPressed: _ctrl.isBusy ? null : _popCancel,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(
            strings.nidScreenTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          actions: [
            if (!_ctrl.isEmpty && cfg.pageList.allowBatchFilterApply)
              IconButton(
                tooltip: strings.applyFilterToAllButton,
                onPressed: _ctrl.isBusy ? null : _showBatchFilterSheet,
                icon: Icon(ui.icons.filter),
              ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _NidSideCardSlot(
                          title: strings.nidFrontLabel,
                          emptyLabel: strings.nidTapToScanFront,
                          page: _frontPage,
                          cardAspectRatio: nidCfg.isoCardAspectRatio,
                          ui: ui,
                          isBusy: _ctrl.isBusy,
                          onTapEmpty: () => _captureSlot(isFront: true),
                          onTapPreview: () {
                            if (_frontPage != null) {
                              unawaited(
                                _openEditorFor(_frontPage!, isFront: true),
                              );
                            }
                          },
                          onRetake: () => _captureSlot(isFront: true),
                          onCrop: _frontPage == null
                              ? null
                              : () => _openCropFor(_frontPage!),
                          onRotate: _frontPage == null
                              ? null
                              : () => _ctrl.rotatePage(_frontPage!.id),
                        ),
                        if (_needsBack) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Center(
                              child: IconButton.outlined(
                                tooltip: strings.nidSwapSidesTooltip,
                                onPressed:
                                    _frontPage != null &&
                                        _backPage != null &&
                                        !_ctrl.isBusy
                                    ? _ctrl.swapFrontAndBack
                                    : null,
                                icon: Icon(ui.icons.swapSides),
                              ),
                            ),
                          ),
                          _NidSideCardSlot(
                            title: strings.nidBackLabel,
                            emptyLabel: strings.nidTapToScanBack,
                            page: _backPage,
                            cardAspectRatio: nidCfg.isoCardAspectRatio,
                            ui: ui,
                            isBusy: _ctrl.isBusy,
                            onTapEmpty: () => _captureSlot(isFront: false),
                            onTapPreview: () {
                              if (_backPage != null) {
                                unawaited(
                                  _openEditorFor(_backPage!, isFront: false),
                                );
                              }
                            },
                            onRetake: () => _captureSlot(isFront: false),
                            onCrop: _backPage == null
                                ? null
                                : () => _openCropFor(_backPage!),
                            onRotate: _backPage == null
                                ? null
                                : () => _ctrl.rotatePage(_backPage!.id),
                          ),
                        ],
                        if (_needsBack && nidCfg.allowLayoutSwitchInUi) ...[
                          const SizedBox(height: 20),
                          Text(
                            'PDF Page Layout',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _layoutChip(
                                NidPdfLayout.topAndBottomSinglePage,
                                strings.nidTopBottomLayoutLabel,
                                theme,
                              ),
                              _layoutChip(
                                NidPdfLayout.sideBySideSinglePage,
                                strings.nidSideBySideLayoutLabel,
                                theme,
                              ),
                              _layoutChip(
                                NidPdfLayout.separatePages,
                                strings.nidSeparatePagesLayoutLabel,
                                theme,
                              ),
                            ],
                          ),
                        ],
                        if (nidCfg.allowPrintSizeSwitchInUi &&
                            _selectedLayout != NidPdfLayout.separatePages) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Card Size on ${nidCfg.targetPageSize.name.toUpperCase()} Sheet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _sizeChip(
                                NidCardPrintSize.readableMedium,
                                'Readable',
                                theme,
                              ),
                              _sizeChip(
                                NidCardPrintSize.actualIsoId1,
                                '1:1 ID Size (85.6×54mm)',
                                theme,
                              ),
                              _sizeChip(
                                NidCardPrintSize.largeFit,
                                'Large Fit',
                                theme,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.surfaceColor,
                      border: Border(top: BorderSide(color: theme.borderColor)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: theme.onPrimaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isReadyToExport && !_ctrl.isBusy
                            ? _exportNidPdf
                            : null,
                        icon: Icon(ui.icons.generatePdf, size: 19),
                        label: Text(strings.generatePdfButton),
                      ),
                    ),
                  ),
                ],
              ),
              if (_ctrl.isBusy)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x77000000),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: theme.surfaceColor,
                          borderRadius: BorderRadius.circular(
                            theme.borderRadius,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: theme.primaryColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _ctrl.isGeneratingPdf
                                  ? strings.generatingPdfTitle
                                  : strings.processingBatchTitle,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutChip(NidPdfLayout value, String label, ScannerThemeData theme) {
    final selected = _selectedLayout == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: theme.primaryColor,
      labelStyle: TextStyle(
        color: selected ? theme.onPrimaryColor : theme.textColor,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 12.5,
      ),
      onSelected: _ctrl.isBusy
          ? null
          : (_) => setState(() => _selectedLayout = value),
    );
  }

  Widget _sizeChip(
    NidCardPrintSize value,
    String label,
    ScannerThemeData theme,
  ) {
    final selected = _selectedPrintSize == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: theme.primaryColor,
      labelStyle: TextStyle(
        color: selected ? theme.onPrimaryColor : theme.textColor,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 12.5,
      ),
      onSelected: _ctrl.isBusy
          ? null
          : (_) => setState(() => _selectedPrintSize = value),
    );
  }
}

class _NidSideCardSlot extends StatelessWidget {
  const _NidSideCardSlot({
    required this.title,
    required this.emptyLabel,
    required this.page,
    required this.cardAspectRatio,
    required this.ui,
    required this.isBusy,
    required this.onTapEmpty,
    required this.onTapPreview,
    required this.onRetake,
    this.onCrop,
    this.onRotate,
  });

  final String title;
  final String emptyLabel;
  final ScannedPage? page;
  final double cardAspectRatio;
  final ScannerUiConfig ui;
  final bool isBusy;
  final VoidCallback onTapEmpty;
  final VoidCallback onTapPreview;
  final VoidCallback onRetake;
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final strings = ui.strings;
    final p = page;
    final hasWarning = p != null && p.quality.decision != QualityDecision.pass;

    return Material(
      color: theme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.borderRadius),
        side: BorderSide(color: theme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(ui.icons.nidCard, size: 18, color: theme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: theme.textColor,
                    ),
                  ),
                ),
                if (p != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      strings.labelForFilter(p.filter),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: cardAspectRatio > 0 ? cardAspectRatio : 1.5858,
              child: p == null
                  ? InkWell(
                      onTap: isBusy ? null : onTapEmpty,
                      borderRadius: BorderRadius.circular(10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.backgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.borderColor),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              size: 32,
                              color: theme.primaryColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              emptyLabel,
                              style: TextStyle(
                                color: theme.secondaryTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : InkWell(
                      onTap: isBusy ? null : onTapPreview,
                      borderRadius: BorderRadius.circular(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: theme.backgroundColor,
                              child: Image.file(
                                File(p.exportPath),
                                key: ValueKey(p.exportPath),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                            if (hasWarning && p.quality.headline != null)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  color: Colors.black87,
                                  child: Text(
                                    p.quality.headline!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.warningColor,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (p != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: isBusy ? null : onCrop,
                    icon: Icon(ui.icons.crop, size: 17),
                    label: Text(strings.cropButton),
                  ),
                  TextButton.icon(
                    onPressed: isBusy ? null : onRotate,
                    icon: Icon(ui.icons.rotate, size: 17),
                    label: Text(strings.rotateButton),
                  ),
                  TextButton.icon(
                    onPressed: isBusy ? null : onRetake,
                    icon: Icon(ui.icons.retake, size: 17),
                    label: Text(strings.retakeButton),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
