import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/page_list_config.dart';
import '../../config/scanner_ui_config.dart';
import '../../controller/custom_scanner_controller.dart';
import '../../domain/page_quality.dart';
import '../../domain/scanned_page.dart';

/// Standalone **embeddable** reorderable list/grid widget for [CustomScannerController].
///
/// Host apps can embed [ScannedPagesReorderableView] directly inside any custom
/// screen, form, tab, or bottom sheet to display, drag-reorder, rotate, edit,
/// and delete scanned pages.
class ScannedPagesReorderableView extends StatelessWidget {
  /// Creates a [ScannedPagesReorderableView].
  const ScannedPagesReorderableView({
    required this.controller,
    this.gridMode = false,
    this.onPageTap,
    this.onStartScan,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });

  /// Controller holding the local ordered list of [ScannedPage] items.
  final CustomScannerController controller;

  /// Renders a multi-column drag-reorderable grid when `true`, or a vertical
  /// `ReorderableListView` when `false`.
  final bool gridMode;

  /// Called when the user taps a page card/row (e.g. to open `PageEditorScreen`).
  final ValueChanged<ScannedPage>? onPageTap;

  /// Called by the empty-state CTA button when 0 pages exist.
  final VoidCallback? onStartScan;

  /// Outer list/grid padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cfg = controller.config;
        final ui = cfg.ui;
        final listCfg = cfg.pageList;
        final pages = controller.pages;

        if (pages.isEmpty) {
          if (ui.emptyStateBuilder != null) {
            return ui.emptyStateBuilder!(context, onStartScan ?? () {});
          }
          return _DefaultEmptyState(
            theme: ui.theme,
            strings: ui.strings,
            onStartScan: onStartScan,
          );
        }

        if (gridMode) {
          return _ReorderableGrid(
            controller: controller,
            pages: pages,
            listCfg: listCfg,
            ui: ui,
            padding: padding,
            onPageTap: onPageTap,
          );
        }

        if (!listCfg.enableReorder) {
          return ListView.separated(
            padding: padding,
            itemCount: pages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _buildTile(context, pages[i], i, ui),
          );
        }

        return ReorderableListView.builder(
          padding: padding,
          itemCount: pages.length,
          onReorder: controller.reorder,
          itemBuilder: (context, i) {
            final page = pages[i];
            return Padding(
              key: ValueKey(page.id),
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildTile(context, page, i, ui),
            );
          },
        );
      },
    );
  }

  Widget _buildTile(
    BuildContext context,
    ScannedPage page,
    int index,
    ScannerUiConfig ui,
  ) {
    void handleTap() => onPageTap?.call(page);
    Future<void> handleDelete() async {
      if (controller.config.pageList.confirmBeforeDelete) {
        final ok = await _confirmDelete(context, ui);
        if (!ok) return;
      }
      await controller.removePage(page.id);
    }

    if (ui.pageTileBuilder != null) {
      return ui.pageTileBuilder!(
        context,
        page,
        index,
        handleTap,
        () => handleDelete(),
      );
    }

    return _DefaultListRow(
      page: page,
      index: index,
      controller: controller,
      onTap: handleTap,
      onDelete: handleDelete,
    );
  }

  Future<bool> _confirmDelete(BuildContext context, ScannerUiConfig ui) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ui.strings.deleteButton}?'),
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
            child: Text(ui.strings.deleteButton),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _DefaultListRow extends StatelessWidget {
  const _DefaultListRow({
    required this.page,
    required this.index,
    required this.controller,
    required this.onTap,
    required this.onDelete,
  });

  final ScannedPage page;
  final int index;
  final CustomScannerController controller;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    final listCfg = cfg.pageList;
    final ui = cfg.ui;
    final theme = ui.theme;
    final strings = ui.strings;
    final hasWarning =
        listCfg.showQualityWarnings &&
        page.quality.decision != QualityDecision.pass;

    return Material(
      color: theme.surfaceColor,
      elevation: theme.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.borderRadius),
        side: BorderSide(color: theme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 54,
                  height: 72,
                  color: theme.backgroundColor,
                  child: Image(
                    image: ResizeImage(
                      FileImage(File(page.listPreviewPath)),
                      width: 180,
                    ),
                    key: ValueKey(page.listPreviewPath),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (listCfg.showPageNumbers)
                          Text(
                            '${strings.pageLabelPrefix} ${page.pageNumber}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: theme.textColor,
                            ),
                          ),
                        if (hasWarning) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: page.quality.decision == QualityDecision.fail
                                ? theme.dangerColor
                                : theme.warningColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (listCfg.showFilterBadges)
                      Text(
                        '${strings.labelForFilter(page.filter)} · ${page.width}×${page.height}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.secondaryTextColor,
                        ),
                      ),
                    if (hasWarning && page.quality.headline != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        page.quality.headline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.warningColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (listCfg.allowRotate)
                IconButton(
                  tooltip: strings.rotateButton,
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.rotatePage(page.id),
                  icon: Icon(
                    ui.icons.rotate,
                    size: 20,
                    color: theme.secondaryTextColor,
                  ),
                ),
              if (listCfg.allowDelete)
                IconButton(
                  tooltip: strings.deleteButton,
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.isBusy ? null : onDelete,
                  icon: Icon(
                    ui.icons.delete,
                    size: 20,
                    color: theme.dangerColor,
                  ),
                ),
              if (listCfg.enableReorder)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      ui.icons.dragHandle,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderableGrid extends StatelessWidget {
  const _ReorderableGrid({
    required this.controller,
    required this.pages,
    required this.listCfg,
    required this.ui,
    required this.padding,
    required this.onPageTap,
  });

  final CustomScannerController controller;
  final List<ScannedPage> pages;
  final PageListConfig listCfg;
  final ScannerUiConfig ui;
  final EdgeInsetsGeometry padding;
  final ValueChanged<ScannedPage>? onPageTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: listCfg.gridCrossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: listCfg.gridChildAspectRatio,
      ),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        final card = _GridPageCard(
          page: page,
          controller: controller,
          onTap: () => onPageTap?.call(page),
          onDelete: () => controller.removePage(page.id),
        );

        if (!listCfg.enableReorder) return card;

        return DragTarget<int>(
          key: ValueKey(page.id),
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) =>
              controller.movePage(details.data, index),
          builder: (context, candidateData, _) {
            final highlighted = candidateData.isNotEmpty;
            return LongPressDraggable<int>(
              data: index,
              feedback: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(ui.theme.borderRadius),
                child: SizedBox(width: 140, height: 190, child: card),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: card),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ui.theme.borderRadius),
                  border: highlighted
                      ? Border.all(color: ui.theme.primaryColor, width: 2.5)
                      : null,
                ),
                child: card,
              ),
            );
          },
        );
      },
    );
  }
}

class _GridPageCard extends StatelessWidget {
  const _GridPageCard({
    required this.page,
    required this.controller,
    required this.onTap,
    required this.onDelete,
  });

  final ScannedPage page;
  final CustomScannerController controller;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    final listCfg = cfg.pageList;
    final ui = cfg.ui;
    final theme = ui.theme;
    final strings = ui.strings;
    final hasWarning =
        listCfg.showQualityWarnings &&
        page.quality.decision != QualityDecision.pass;

    return Material(
      color: theme.surfaceColor,
      elevation: theme.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.borderRadius),
        side: BorderSide(color: theme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: theme.backgroundColor,
                    child: Image(
                      image: ResizeImage(
                        FileImage(File(page.listPreviewPath)),
                        width: 260,
                      ),
                      key: ValueKey(page.listPreviewPath),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  if (listCfg.showPageNumbers)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${page.pageNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (hasWarning)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.warningColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.priority_high_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      listCfg.showFilterBadges
                          ? strings.labelForFilter(page.filter)
                          : '${strings.pageLabelPrefix} ${page.pageNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.textColor,
                      ),
                    ),
                  ),
                  if (listCfg.allowDelete)
                    InkWell(
                      onTap: controller.isBusy ? null : onDelete,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          ui.icons.delete,
                          size: 17,
                          color: theme.dangerColor,
                        ),
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

class _DefaultEmptyState extends StatelessWidget {
  const _DefaultEmptyState({
    required this.theme,
    required this.strings,
    this.onStartScan,
  });

  final ScannerThemeData theme;
  final ScannerStrings strings;
  final VoidCallback? onStartScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 56,
              color: theme.secondaryTextColor,
            ),
            const SizedBox(height: 16),
            Text(
              strings.emptyPagesTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              strings.emptyPagesSubtitle,
              style: TextStyle(fontSize: 14, color: theme.secondaryTextColor),
              textAlign: TextAlign.center,
            ),
            if (onStartScan != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.onPrimaryColor,
                ),
                onPressed: onStartScan,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(strings.startScanningButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
