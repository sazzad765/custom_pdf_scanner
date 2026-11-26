/// Display mode for the local reorderable scanned pages view.
enum PageListLayout {
  /// Reorderable vertical list showing page thumbnail, title, filter, quality,
  /// and quick actions (`ReorderableListView`).
  list,

  /// Multi-column card grid with drag-and-drop reordering.
  grid,

  /// Starts in list/grid and shows a toolbar toggle so the user can switch
  /// between list and grid views.
  toggleable,
}

/// Configuration for the local reorderable page list and per-page/batch actions.
class PageListConfig {
  /// Creates a [PageListConfig].
  const PageListConfig({
    this.enableReorder = true,
    this.layout = PageListLayout.toggleable,
    this.initialGridView = false,
    this.gridCrossAxisCount = 2,
    this.gridChildAspectRatio = 0.72,
    this.allowAddMore = true,
    this.allowAddSingleOrMultiChoice = true,
    this.allowEditCrop = true,
    this.allowChangeFilter = true,
    this.allowBatchFilterApply = true,
    this.allowRotate = true,
    this.allowRetake = true,
    this.allowDelete = true,
    this.confirmBeforeDelete = false,
    this.confirmBeforeDiscardAll = true,
    this.showQualityWarnings = true,
    this.showFilterBadges = true,
    this.showPageNumbers = true,
  });

  /// Enables drag-and-drop page reordering.
  final bool enableReorder;

  /// List, grid, or user-toggleable layout.
  final PageListLayout layout;

  /// Starts in grid mode when [layout] is [PageListLayout.toggleable].
  final bool initialGridView;

  /// Number of columns in grid layout.
  final int gridCrossAxisCount;

  /// Card aspect ratio (`width / height`) in grid layout.
  final double gridChildAspectRatio;

  /// Shows the "+ Add More" button to scan and append additional single or
  /// multi-page batches into the existing list.
  final bool allowAddMore;

  /// Lets the user pick between "+ Scan Multi-Page" and "+ Scan Single Page"
  /// when tapping Add More.
  final bool allowAddSingleOrMultiChoice;

  /// Allows re-opening the 4-corner perspective crop editor on any page.
  final bool allowEditCrop;

  /// Allows changing the OpenCV filter of individual pages.
  final bool allowChangeFilter;

  /// Shows an "Apply filter to all pages" batch action.
  final bool allowBatchFilterApply;

  /// Allows 90° clockwise rotation of individual pages.
  final bool allowRotate;

  /// Allows retaking/replacing an existing page in place.
  final bool allowRetake;

  /// Allows removing pages from the list.
  final bool allowDelete;

  /// Prompts for confirmation before deleting a single page.
  final bool confirmBeforeDelete;

  /// Prompts for confirmation before discarding the entire session on back/close.
  final bool confirmBeforeDiscardAll;

  /// Displays advisory quality warning badges (e.g. blur/glare) on page items.
  final bool showQualityWarnings;

  /// Displays the active filter name (`Magic Color`, `B&W`, etc.) on page items.
  final bool showFilterBadges;

  /// Displays 1-based page numbers on page items.
  final bool showPageNumbers;

  /// Creates a modified copy of this [PageListConfig].
  PageListConfig copyWith({
    bool? enableReorder,
    PageListLayout? layout,
    bool? initialGridView,
    int? gridCrossAxisCount,
    double? gridChildAspectRatio,
    bool? allowAddMore,
    bool? allowAddSingleOrMultiChoice,
    bool? allowEditCrop,
    bool? allowChangeFilter,
    bool? allowBatchFilterApply,
    bool? allowRotate,
    bool? allowRetake,
    bool? allowDelete,
    bool? confirmBeforeDelete,
    bool? confirmBeforeDiscardAll,
    bool? showQualityWarnings,
    bool? showFilterBadges,
    bool? showPageNumbers,
  }) => PageListConfig(
    enableReorder: enableReorder ?? this.enableReorder,
    layout: layout ?? this.layout,
    initialGridView: initialGridView ?? this.initialGridView,
    gridCrossAxisCount: gridCrossAxisCount ?? this.gridCrossAxisCount,
    gridChildAspectRatio: gridChildAspectRatio ?? this.gridChildAspectRatio,
    allowAddMore: allowAddMore ?? this.allowAddMore,
    allowAddSingleOrMultiChoice:
        allowAddSingleOrMultiChoice ?? this.allowAddSingleOrMultiChoice,
    allowEditCrop: allowEditCrop ?? this.allowEditCrop,
    allowChangeFilter: allowChangeFilter ?? this.allowChangeFilter,
    allowBatchFilterApply: allowBatchFilterApply ?? this.allowBatchFilterApply,
    allowRotate: allowRotate ?? this.allowRotate,
    allowRetake: allowRetake ?? this.allowRetake,
    allowDelete: allowDelete ?? this.allowDelete,
    confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
    confirmBeforeDiscardAll:
        confirmBeforeDiscardAll ?? this.confirmBeforeDiscardAll,
    showQualityWarnings: showQualityWarnings ?? this.showQualityWarnings,
    showFilterBadges: showFilterBadges ?? this.showFilterBadges,
    showPageNumbers: showPageNumbers ?? this.showPageNumbers,
  );
}
