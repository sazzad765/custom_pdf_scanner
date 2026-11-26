import 'package:flutter/material.dart';

import '../domain/scan_filter.dart';
import '../domain/scanned_page.dart';

/// Custom builder for individual page items in the reorderable list/grid.
typedef ScannerPageTileBuilder =
    Widget Function(
      BuildContext context,
      ScannedPage page,
      int index,
      VoidCallback onTap,
      VoidCallback onDelete,
    );

/// Custom builder for the empty-list state when 0 pages are present.
typedef ScannerEmptyStateBuilder =
    Widget Function(BuildContext context, VoidCallback onStartScan);

/// Custom builder for the bottom action bar on the reorderable pages screen.
typedef ScannerBottomBarBuilder =
    Widget Function(
      BuildContext context,
      int pageCount,
      bool isBusy,
      VoidCallback? onAddMore,
      VoidCallback? onGeneratePdf,
    );

/// Visual theme tokens for all built-in `custom_pdf_scanner` screens and widgets.
class ScannerThemeData {
  /// Creates a custom [ScannerThemeData].
  const ScannerThemeData({
    this.brightness = Brightness.light,
    this.primaryColor = const Color(0xFF0F766E),
    this.onPrimaryColor = Colors.white,
    this.backgroundColor = const Color(0xFFF8FAFC),
    this.surfaceColor = Colors.white,
    this.textColor = const Color(0xFF0F172A),
    this.secondaryTextColor = const Color(0xFF64748B),
    this.borderColor = const Color(0xFFE2E8F0),
    this.warningColor = const Color(0xFFD97706),
    this.dangerColor = const Color(0xFFDC2626),
    this.successColor = const Color(0xFF16A34A),
    this.cropFrameColor = const Color(0xFF14B8A6),
    this.cropOutsideMaskColor = const Color(0x880B1220),
    this.borderRadius = 12.0,
    this.cardElevation = 0.0,
  });

  /// Clean light theme preset.
  factory ScannerThemeData.light({
    Color primaryColor = const Color(0xFF0F766E),
  }) => ScannerThemeData(primaryColor: primaryColor);

  /// Dark theme preset.
  factory ScannerThemeData.dark({
    Color primaryColor = const Color(0xFF14B8A6),
  }) => ScannerThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    onPrimaryColor: const Color(0xFF042F2E),
    backgroundColor: const Color(0xFF0B1120),
    surfaceColor: const Color(0xFF1E293B),
    textColor: const Color(0xFFF8FAFC),
    secondaryTextColor: const Color(0xFF94A3B8),
    borderColor: const Color(0xFF334155),
    cropFrameColor: primaryColor,
  );

  /// Overall brightness (`light` or `dark`).
  final Brightness brightness;

  /// Primary accent color for buttons, active filter chips, and badges.
  final Color primaryColor;

  /// Foreground color drawn on top of [primaryColor].
  final Color onPrimaryColor;

  /// Scaffold background color.
  final Color backgroundColor;

  /// Card, sheet, and toolbar surface color.
  final Color surfaceColor;

  /// Primary text color.
  final Color textColor;

  /// Muted / subtitle text color.
  final Color secondaryTextColor;

  /// Hairline divider and card border color.
  final Color borderColor;

  /// Advisory warning badge color.
  final Color warningColor;

  /// Destructive action and error color.
  final Color dangerColor;

  /// Positive status color (e.g. stable camera edge lock).
  final Color successColor;

  /// Stroke/handle color for the 4-corner perspective cropper and camera overlay.
  final Color cropFrameColor;

  /// Scrim color drawn outside the crop quadrilateral.
  final Color cropOutsideMaskColor;

  /// Corner radius used for cards, sheets, and buttons.
  final double borderRadius;

  /// Material elevation for page cards.
  final double cardElevation;
}

/// Customizable UI strings for localization (i18n) across all scanner screens.
class ScannerStrings {
  /// Creates [ScannerStrings] with English defaults.
  const ScannerStrings({
    this.pagesScreenTitle = 'Scanned Pages',
    this.cameraScreenTitle = 'Scan Document',
    this.editPageTitle = 'Edit Page',
    this.cropPageTitle = 'Adjust Corners',
    this.nidScreenTitle = 'Scan NID Card',
    this.nidFrontLabel = 'Front Side',
    this.nidBackLabel = 'Back Side',
    this.nidTapToScanFront = 'Tap to scan Front Side',
    this.nidTapToScanBack = 'Tap to scan Back Side',
    this.nidCameraFrontHint = 'Align FRONT side of NID card inside frame',
    this.nidCameraBackHint = 'Align BACK side of NID card inside frame',
    this.nidSwapSidesTooltip = 'Swap Front & Back',
    this.nidTopBottomLayoutLabel = '1 Page (Top & Bottom)',
    this.nidSideBySideLayoutLabel = '1 Page (Side-by-Side)',
    this.nidSeparatePagesLayoutLabel = '2 Separate Pages',
    this.addMoreButton = 'Add More',
    this.addMultiPageOption = 'Scan Multiple Pages',
    this.addSinglePageOption = 'Scan Single Page',
    this.generatePdfButton = 'Generate PDF',
    this.confirmPageButton = 'Done',
    this.applyCropButton = 'Apply Crop',
    this.resetFullImageButton = 'Full Image',
    this.retakeButton = 'Retake',
    this.rotateButton = 'Rotate',
    this.cropButton = 'Crop',
    this.deleteButton = 'Delete',
    this.applyFilterToAllButton = 'Apply Filter to All',
    this.emptyPagesTitle = 'No pages scanned yet',
    this.emptyPagesSubtitle = 'Tap below to capture one or more pages.',
    this.startScanningButton = 'Start Scanning',
    this.processingBatchTitle = 'Enhancing scanned pages…',
    this.generatingPdfTitle = 'Generating PDF…',
    this.discardDialogTitle = 'Discard scanned pages?',
    this.discardDialogBody =
        'Leaving now will discard all scanned pages in this session.',
    this.discardConfirmLabel = 'Discard',
    this.cancelLabel = 'Cancel',
    this.pageLabelPrefix = 'Page',
    this.reorderHint = 'Drag pages to reorder',
    this.filterLabels = const {},
  });

  /// Title of the reorderable pages list screen.
  final String pagesScreenTitle;

  /// Title of the custom camera screen.
  final String cameraScreenTitle;

  /// Title of the single-page preview/filter screen.
  final String editPageTitle;

  /// Title of the 4-corner perspective crop screen.
  final String cropPageTitle;

  /// Title of the dedicated NID card scan screen.
  final String nidScreenTitle;

  /// Label for the Front side slot of an NID card.
  final String nidFrontLabel;

  /// Label for the Back side slot of an NID card.
  final String nidBackLabel;

  /// Placeholder prompt inside an empty Front NID slot.
  final String nidTapToScanFront;

  /// Placeholder prompt inside an empty Back NID slot.
  final String nidTapToScanBack;

  /// Camera overlay hint when capturing the Front side of an NID card.
  final String nidCameraFrontHint;

  /// Camera overlay hint when capturing the Back side of an NID card.
  final String nidCameraBackHint;

  /// Tooltip for swapping Front and Back NID slots.
  final String nidSwapSidesTooltip;

  /// Label for `NidPdfLayout.topAndBottomSinglePage`.
  final String nidTopBottomLayoutLabel;

  /// Label for `NidPdfLayout.sideBySideSinglePage`.
  final String nidSideBySideLayoutLabel;

  /// Label for `NidPdfLayout.separatePages`.
  final String nidSeparatePagesLayoutLabel;

  /// Label for the "+ Add More" button.
  final String addMoreButton;

  /// Bottom-sheet option to append a multi-page scan batch.
  final String addMultiPageOption;

  /// Bottom-sheet option to append a single-page scan.
  final String addSinglePageOption;

  /// Primary CTA label to build and return the final PDF.
  final String generatePdfButton;

  /// Confirm button in single-page editor.
  final String confirmPageButton;

  /// Confirm button in manual crop editor.
  final String applyCropButton;

  /// Button to expand crop corners to the full image bounds.
  final String resetFullImageButton;

  /// Label for retaking a page.
  final String retakeButton;

  /// Label for 90° clockwise rotation.
  final String rotateButton;

  /// Label for opening the perspective crop editor.
  final String cropButton;

  /// Label for deleting a page.
  final String deleteButton;

  /// Label for applying a filter to every page in the list.
  final String applyFilterToAllButton;

  /// Headline shown when the page list is empty.
  final String emptyPagesTitle;

  /// Subtitle shown when the page list is empty.
  final String emptyPagesSubtitle;

  /// CTA button shown when the page list is empty.
  final String startScanningButton;

  /// Progress message shown during multi-page OpenCV batch enhancement.
  final String processingBatchTitle;

  /// Progress message shown while streaming pages to PDF.
  final String generatingPdfTitle;

  /// Title of the discard confirmation dialog.
  final String discardDialogTitle;

  /// Body text of the discard confirmation dialog.
  final String discardDialogBody;

  /// Destructive button label in the discard dialog.
  final String discardConfirmLabel;

  /// Cancel button label.
  final String cancelLabel;

  /// Prefix before page numbers (e.g. `"Page"` -> `"Page 1"`).
  final String pageLabelPrefix;

  /// Subtitle hint shown when reordering is enabled.
  final String reorderHint;

  /// Optional localized overrides for [ScanFilter] names.
  final Map<ScanFilter, String> filterLabels;

  /// Returns the localized label for [filter].
  String labelForFilter(ScanFilter filter) =>
      filterLabels[filter] ?? filter.defaultLabel;
}

/// Customizable icons used by the built-in scanner UI.
class ScannerIcons {
  /// Creates [ScannerIcons] with Material defaults.
  const ScannerIcons({
    this.addMore = Icons.add_a_photo_outlined,
    this.generatePdf = Icons.picture_as_pdf_outlined,
    this.crop = Icons.crop_rotate_outlined,
    this.rotate = Icons.rotate_90_degrees_cw_outlined,
    this.filter = Icons.auto_fix_high_outlined,
    this.delete = Icons.delete_outline,
    this.retake = Icons.camera_alt_outlined,
    this.gridView = Icons.grid_view_rounded,
    this.listView = Icons.view_agenda_outlined,
    this.dragHandle = Icons.drag_indicator_rounded,
    this.torchOn = Icons.flash_on_rounded,
    this.torchOff = Icons.flash_off_rounded,
    this.nidCard = Icons.badge_outlined,
    this.swapSides = Icons.swap_vert_rounded,
  });

  /// Icon for "+ Add More".
  final IconData addMore;

  /// Icon for "Generate PDF".
  final IconData generatePdf;

  /// Icon for manual crop action.
  final IconData crop;

  /// Icon for 90° rotation action.
  final IconData rotate;

  /// Icon for filter selection / batch filter.
  final IconData filter;

  /// Icon for page deletion.
  final IconData delete;

  /// Icon for page retake.
  final IconData retake;

  /// Icon to switch to grid layout.
  final IconData gridView;

  /// Icon to switch to list layout.
  final IconData listView;

  /// Drag handle icon in reorderable list mode.
  final IconData dragHandle;

  /// Torch enabled icon.
  final IconData torchOn;

  /// Torch disabled icon.
  final IconData torchOff;

  /// Icon representing an NID / ID card.
  final IconData nidCard;

  /// Icon for swapping Front and Back NID sides.
  final IconData swapSides;
}

/// UI customization and slot builders for `custom_pdf_scanner`.
class ScannerUiConfig {
  /// Creates a [ScannerUiConfig].
  const ScannerUiConfig({
    this.theme = const ScannerThemeData(),
    this.strings = const ScannerStrings(),
    this.icons = const ScannerIcons(),
    this.pageTileBuilder,
    this.emptyStateBuilder,
    this.bottomBarBuilder,
  });

  /// Colors, surface radii, and elevation tokens.
  final ScannerThemeData theme;

  /// All user-facing text labels.
  final ScannerStrings strings;

  /// All action icons.
  final ScannerIcons icons;

  /// Optional custom item builder for pages in the reorderable list/grid.
  final ScannerPageTileBuilder? pageTileBuilder;

  /// Optional custom empty-state builder when 0 pages have been scanned.
  final ScannerEmptyStateBuilder? emptyStateBuilder;

  /// Optional custom bottom bar builder on the reorderable pages screen.
  final ScannerBottomBarBuilder? bottomBarBuilder;
}
