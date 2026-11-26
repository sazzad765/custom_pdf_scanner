import 'dart:io';

import 'package:flutter/material.dart';

import '../../controller/custom_scanner_controller.dart';
import '../../domain/page_quality.dart';
import '../../domain/scan_filter.dart';
import '../../domain/scanned_page.dart';
import 'page_crop_screen.dart';

/// Action selected when closing [PageEditorScreen].
enum PageEditorOutcome {
  /// User confirmed the page (proceed to PDF or return to list).
  confirmed,

  /// User requested retaking this page.
  retake,

  /// User deleted this page.
  deleted,
}

/// Interactive single-page preview, filter switcher, rotation, and crop screen.
class PageEditorScreen extends StatefulWidget {
  /// Creates a [PageEditorScreen].
  const PageEditorScreen({
    required this.controller,
    required this.pageId,
    this.primaryButtonLabel,
    this.allowRetake = true,
    this.allowDelete = true,
    super.key,
  });

  /// Active scanner controller.
  final CustomScannerController controller;

  /// ID of the [ScannedPage] being inspected/edited.
  final String pageId;

  /// Optional override for the primary confirm button label (e.g. `"Generate PDF"`
  /// in `ScanMode.singlePage` with `SinglePageBehavior.reviewThenPdf`).
  final String? primaryButtonLabel;

  /// Shows the Retake action when `true`.
  final bool allowRetake;

  /// Shows the Delete action in the AppBar when `true`.
  final bool allowDelete;

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  ScannedPage? get _page => widget.controller.pageById(widget.pageId);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _changeFilter(ScanFilter filter) async {
    final p = _page;
    if (p == null || p.filter == filter || widget.controller.isBusy) return;
    await widget.controller.applyFilter(widget.pageId, filter);
  }

  Future<void> _rotate() async {
    if (widget.controller.isBusy) return;
    await widget.controller.rotatePage(widget.pageId);
  }

  Future<void> _openCrop() async {
    if (widget.controller.isBusy) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PageCropScreen(
          controller: widget.controller,
          pageId: widget.pageId,
        ),
      ),
    );
  }

  Future<void> _deletePage() async {
    await widget.controller.removePage(widget.pageId);
    if (mounted) Navigator.of(context).pop(PageEditorOutcome.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final cfg = widget.controller.config;
    final ui = cfg.ui;
    final theme = ui.theme;
    final strings = ui.strings;

    if (page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final filters = cfg.processing.availableFilters;
    final qualityHeadline = cfg.pageList.showQualityWarnings
        ? page.quality.headline
        : null;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.surfaceColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: Text('${strings.pageLabelPrefix} ${page.pageNumber}'),
        actions: [
          if (widget.allowRetake && cfg.pageList.allowRetake)
            IconButton(
              tooltip: strings.retakeButton,
              onPressed: widget.controller.isBusy
                  ? null
                  : () => Navigator.of(context).pop(PageEditorOutcome.retake),
              icon: Icon(ui.icons.retake),
            ),
          if (widget.allowDelete && cfg.pageList.allowDelete)
            IconButton(
              tooltip: strings.deleteButton,
              onPressed: widget.controller.isBusy ? null : _deletePage,
              icon: Icon(ui.icons.delete, color: theme.dangerColor),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (qualityHeadline != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: page.quality.decision == QualityDecision.fail
                    ? theme.dangerColor.withValues(alpha: 0.14)
                    : theme.warningColor.withValues(alpha: 0.14),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: page.quality.decision == QualityDecision.fail
                          ? theme.dangerColor
                          : theme.warningColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        qualityHeadline,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.5,
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.file(
                              File(page.exportPath),
                              key: ValueKey(page.exportPath),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.controller.isBusy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: theme.surfaceColor,
                              borderRadius: BorderRadius.circular(
                                theme.borderRadius,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: theme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Enhancing…',
                                  style: TextStyle(color: theme.textColor),
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
            Container(
              decoration: BoxDecoration(
                color: theme.surfaceColor,
                border: Border(top: BorderSide(color: theme.borderColor)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cfg.pageList.allowChangeFilter && filters.length > 1) ...[
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: filters.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final f = filters[i];
                          final selected = page.filter == f;
                          return ChoiceChip(
                            label: Text(strings.labelForFilter(f)),
                            selected: selected,
                            selectedColor: theme.primaryColor,
                            labelStyle: TextStyle(
                              color: selected
                                  ? theme.onPrimaryColor
                                  : theme.textColor,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            onSelected: widget.controller.isBusy
                                ? null
                                : (_) => _changeFilter(f),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      if (cfg.pageList.allowEditCrop) ...[
                        OutlinedButton.icon(
                          onPressed: widget.controller.isBusy
                              ? null
                              : _openCrop,
                          icon: Icon(ui.icons.crop, size: 18),
                          label: Text(strings.cropButton),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (cfg.pageList.allowRotate) ...[
                        OutlinedButton.icon(
                          onPressed: widget.controller.isBusy ? null : _rotate,
                          icon: Icon(ui.icons.rotate, size: 18),
                          label: Text(strings.rotateButton),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: theme.onPrimaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: widget.controller.isBusy
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pop(PageEditorOutcome.confirmed),
                          child: Text(
                            widget.primaryButtonLabel ??
                                strings.confirmPageButton,
                          ),
                        ),
                      ),
                    ],
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
