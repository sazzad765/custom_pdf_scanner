import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/capture_config.dart';
import '../../config/page_list_config.dart';
import '../../config/scanner_ui_config.dart';
import '../../controller/custom_scanner_controller.dart';
import '../../domain/scan_filter.dart';
import '../../domain/scanned_page.dart';
import '../../domain/scanned_pdf_result.dart';
import '../../infrastructure/camera/page_capture_service.dart';
import '../widgets/scanned_pages_reorderable_view.dart';
import 'multi_shot_camera_screen.dart';
import 'page_crop_screen.dart';
import 'page_editor_screen.dart';

/// Complete turnkey scanner screen orchestrating:
/// * **Single-page mode** (`immediatePdf`, `reviewThenPdf`, or `addToPageList`)
/// * **Multi-page mode** (batch capture -> sequential OpenCV batch processing ->
///   local reorderable page list -> "+ Add More" -> batch filter -> local PDF)
class ScannedPagesScreen extends StatefulWidget {
  /// Creates a [ScannedPagesScreen].
  const ScannedPagesScreen({
    required this.controller,
    this.autoLaunchCaptureOnOpen = true,
    this.disposeControllerOnExit = false,
    super.key,
  });

  /// Controller owning the local page list and OpenCV/PDF pipelines.
  final CustomScannerController controller;

  /// Automatically triggers the initial scan when opened with 0 pages.
  final bool autoLaunchCaptureOnOpen;

  /// Disposes [controller] (and cleans up temp files on cancel) when this screen pops.
  final bool disposeControllerOnExit;

  @override
  State<ScannedPagesScreen> createState() => _ScannedPagesScreenState();
}

class _ScannedPagesScreenState extends State<ScannedPagesScreen> {
  late bool _gridMode;
  bool _exiting = false;

  CustomScannerController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    final layout = _ctrl.config.pageList.layout;
    _gridMode = switch (layout) {
      PageListLayout.grid => true,
      PageListLayout.list => false,
      PageListLayout.toggleable => _ctrl.config.pageList.initialGridView,
    };
    _ctrl.addListener(_onControllerChanged);

    if (widget.autoLaunchCaptureOnOpen && _ctrl.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runCaptureFlow(_ctrl.config.capture.scanMode));
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    if (widget.disposeControllerOnExit) {
      unawaited(_ctrl.disposeWorkspaceAndController());
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runCaptureFlow(ScanMode mode, {String? replacePageId}) async {
    if (_ctrl.isBusy) return;
    try {
      List<ScannedPage> added;
      if (_ctrl.shouldUseNativeMlKit()) {
        added = await _ctrl.captureAndProcessWithMlKit(
          modeOverride: mode,
          replacePageId: replacePageId,
        );
      } else {
        if (!mounted) return;
        final maxShots = replacePageId != null || mode == ScanMode.singlePage
            ? 1
            : _ctrl.remainingPageSlots;
        final rawPages = await Navigator.of(context)
            .push<List<CapturedRawPage>>(
              MaterialPageRoute(
                builder: (_) => MultiShotCameraScreen(
                  config: _ctrl.config,
                  scanMode: mode,
                  maxShots: maxShots,
                ),
              ),
            );
        if (!mounted || rawPages == null || rawPages.isEmpty) {
          if (_ctrl.isEmpty &&
              widget.autoLaunchCaptureOnOpen &&
              replacePageId == null) {
            await _popCancel(skipConfirm: true);
          }
          return;
        }
        added = await _ctrl.addCapturedPages(
          rawPages,
          replacePageId: replacePageId,
        );
      }

      if (!mounted) return;
      if (added.isEmpty) {
        if (_ctrl.isEmpty &&
            widget.autoLaunchCaptureOnOpen &&
            replacePageId == null) {
          await _popCancel(skipConfirm: true);
        }
        return;
      }

      // Single-page shortcut behaviors when configured as a single-page session:
      final captureCfg = _ctrl.config.capture;
      if (replacePageId == null &&
          captureCfg.scanMode == ScanMode.singlePage &&
          _ctrl.pageCount == 1 &&
          captureCfg.singlePageBehavior != SinglePageBehavior.addToPageList) {
        final singlePage = added.first;
        if (_ctrl.config.processing.openManualCropOnLowConfidence &&
            singlePage.cropConfidence != null &&
            singlePage.cropConfidence! <
                _ctrl.config.processing.minCropConfidence) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  PageCropScreen(controller: _ctrl, pageId: singlePage.id),
            ),
          );
          if (!mounted) return;
        }

        if (captureCfg.singlePageBehavior == SinglePageBehavior.immediatePdf) {
          await _exportAndPop();
          return;
        }

        if (captureCfg.singlePageBehavior == SinglePageBehavior.reviewThenPdf) {
          final outcome = await Navigator.of(context).push<PageEditorOutcome>(
            MaterialPageRoute(
              builder: (_) => PageEditorScreen(
                controller: _ctrl,
                pageId: singlePage.id,
                primaryButtonLabel: _ctrl.config.ui.strings.generatePdfButton,
                allowDelete: false,
              ),
            ),
          );
          if (!mounted) return;
          if (outcome == PageEditorOutcome.confirmed) {
            await _exportAndPop();
          } else if (outcome == PageEditorOutcome.retake) {
            await _runCaptureFlow(
              ScanMode.singlePage,
              replacePageId: singlePage.id,
            );
          } else {
            await _popCancel(skipConfirm: true);
          }
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _onAddMorePressed() async {
    if (!_ctrl.canAddMore || _ctrl.isBusy) return;
    final listCfg = _ctrl.config.pageList;
    if (!listCfg.allowAddSingleOrMultiChoice) {
      await _runCaptureFlow(_ctrl.config.capture.scanMode);
      return;
    }

    final ui = _ctrl.config.ui;
    final chosenMode = await showModalBottomSheet<ScanMode>(
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
          children: [
            ListTile(
              leading: Icon(
                Icons.burst_mode_outlined,
                color: ui.theme.primaryColor,
              ),
              title: Text(
                ui.strings.addMultiPageOption,
                style: TextStyle(color: ui.theme.textColor),
              ),
              onTap: () => Navigator.of(ctx).pop(ScanMode.multiPage),
            ),
            ListTile(
              leading: Icon(
                Icons.crop_portrait_rounded,
                color: ui.theme.primaryColor,
              ),
              title: Text(
                ui.strings.addSinglePageOption,
                style: TextStyle(color: ui.theme.textColor),
              ),
              onTap: () => Navigator.of(ctx).pop(ScanMode.singlePage),
            ),
          ],
        ),
      ),
    );
    if (chosenMode != null && mounted) {
      await _runCaptureFlow(chosenMode);
    }
  }

  Future<void> _openPageEditor(ScannedPage page) async {
    if (_ctrl.isBusy) return;
    final outcome = await Navigator.of(context).push<PageEditorOutcome>(
      MaterialPageRoute(
        builder: (_) => PageEditorScreen(controller: _ctrl, pageId: page.id),
      ),
    );
    if (!mounted) return;
    if (outcome == PageEditorOutcome.retake) {
      await _runCaptureFlow(ScanMode.singlePage, replacePageId: page.id);
    }
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

  Future<void> _exportAndPop() async {
    if (_ctrl.isEmpty || _ctrl.isBusy) return;
    try {
      final ScannedPdfResult result = await _ctrl.generatePdf();
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
    final listCfg = cfg.pageList;
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${strings.pagesScreenTitle}${_ctrl.isEmpty ? '' : ' (${_ctrl.pageCount})'}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_ctrl.isEmpty && listCfg.enableReorder)
                Text(
                  strings.reorderHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.secondaryTextColor,
                  ),
                ),
            ],
          ),
          actions: [
            if (!_ctrl.isEmpty && listCfg.allowBatchFilterApply)
              IconButton(
                tooltip: strings.applyFilterToAllButton,
                onPressed: _ctrl.isBusy ? null : _showBatchFilterSheet,
                icon: Icon(ui.icons.filter),
              ),
            if (!_ctrl.isEmpty && listCfg.layout == PageListLayout.toggleable)
              IconButton(
                tooltip: _gridMode ? 'List view' : 'Grid view',
                onPressed: () => setState(() => _gridMode = !_gridMode),
                icon: Icon(_gridMode ? ui.icons.listView : ui.icons.gridView),
              ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ScannedPagesReorderableView(
                      controller: _ctrl,
                      gridMode: _gridMode,
                      onPageTap: _openPageEditor,
                      onStartScan: () => _runCaptureFlow(cfg.capture.scanMode),
                    ),
                  ),
                  if (!_ctrl.isEmpty) _buildBottomBar(context, ui, strings),
                ],
              ),
              if (_ctrl.isBusy) _buildProgressOverlay(theme, strings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ScannerUiConfig ui,
    ScannerStrings strings,
  ) {
    if (ui.bottomBarBuilder != null) {
      return ui.bottomBarBuilder!(
        context,
        _ctrl.pageCount,
        _ctrl.isBusy,
        _ctrl.canAddMore ? _onAddMorePressed : null,
        _ctrl.isEmpty ? null : _exportAndPop,
      );
    }

    final theme = ui.theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        border: Border(top: BorderSide(color: theme.borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          if (_ctrl.canAddMore) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryColor,
                side: BorderSide(color: theme.primaryColor),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
              ),
              onPressed: _ctrl.isBusy ? null : _onAddMorePressed,
              icon: Icon(ui.icons.addMore, size: 19),
              label: Text(strings.addMoreButton),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.onPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _ctrl.isBusy ? null : _exportAndPop,
              icon: Icon(ui.icons.generatePdf, size: 19),
              label: Text('${strings.generatePdfButton} (${_ctrl.pageCount})'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressOverlay(ScannerThemeData theme, ScannerStrings strings) {
    final batch = _ctrl.batchProgress;
    final pdf = _ctrl.pdfProgress;

    final String title;
    final String? subtitle;
    final double? progressValue;

    if (_ctrl.isGeneratingPdf && pdf != null) {
      title = strings.generatingPdfTitle;
      subtitle = '${pdf.completedPages} / ${pdf.totalPages}';
      progressValue = pdf.totalPages > 1 ? pdf.fraction : null;
    } else if (batch != null) {
      title = strings.processingBatchTitle;
      subtitle = '${batch.completed} / ${batch.total}';
      progressValue = batch.total > 1 ? batch.fraction : null;
    } else {
      title = strings.processingBatchTitle;
      subtitle = null;
      progressValue = null;
    }

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x77000000),
        child: Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.surfaceColor,
              borderRadius: BorderRadius.circular(theme.borderRadius),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  value: progressValue,
                  color: theme.primaryColor,
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
