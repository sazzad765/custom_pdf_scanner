import 'capture_config.dart';
import 'page_list_config.dart';
import 'pdf_config.dart';
import 'processing_config.dart';
import 'scanner_ui_config.dart';

/// Top-level configuration for `custom_pdf_scanner`, grouping capture, OpenCV
/// processing, local reorderable page list, PDF generation, and UI settings.
class CustomScannerConfig {
  /// Creates a [CustomScannerConfig] with full customization over every module.
  const CustomScannerConfig({
    this.capture = const CaptureConfig(),
    this.processing = const ProcessingConfig(),
    this.pageList = const PageListConfig(),
    this.pdf = const PdfConfig(),
    this.ui = const ScannerUiConfig(),
    this.workingDirectoryPath,
  });

  /// Convenience preset configured for scanning a single page into a PDF.
  factory CustomScannerConfig.singlePage({
    SinglePageBehavior behavior = SinglePageBehavior.reviewThenPdf,
    CaptureBackend backend = CaptureBackend.auto,
    ProcessingConfig processing = const ProcessingConfig(),
    PdfConfig pdf = const PdfConfig(),
    ScannerUiConfig ui = const ScannerUiConfig(),
  }) => CustomScannerConfig(
    capture: CaptureConfig(
      scanMode: ScanMode.singlePage,
      singlePageBehavior: behavior,
      backend: backend,
      maxPages: behavior == SinglePageBehavior.addToPageList ? null : 1,
    ),
    processing: processing,
    pdf: pdf,
    ui: ui,
  );

  /// Convenience preset configured for multi-page batch scanning with OpenCV
  /// batch enhancement, reorderable local page list, and "+ Add More".
  factory CustomScannerConfig.multiPage({
    int? maxPages = 200,
    CaptureBackend backend = CaptureBackend.auto,
    bool allowGalleryImport = true,
    ProcessingConfig processing = const ProcessingConfig(),
    PageListConfig pageList = const PageListConfig(),
    PdfConfig pdf = const PdfConfig(),
    ScannerUiConfig ui = const ScannerUiConfig(),
  }) => CustomScannerConfig(
    capture: CaptureConfig(
      scanMode: ScanMode.multiPage,
      backend: backend,
      maxPages: maxPages,
      allowGalleryImport: allowGalleryImport,
    ),
    processing: processing,
    pageList: pageList,
    pdf: pdf,
    ui: ui,
  );

  /// Camera/scanner acquisition settings (single vs. multi-page, ML Kit vs. custom camera).
  final CaptureConfig capture;

  /// OpenCV crop, filter enhancement, resolution, and quality settings.
  final ProcessingConfig processing;

  /// Reorderable list/grid, "+ Add More", and page editing settings.
  final PageListConfig pageList;

  /// Local streaming PDF layout, metadata, and file output settings.
  final PdfConfig pdf;

  /// Theme, localization strings, icons, and custom widget builders.
  final ScannerUiConfig ui;

  /// Optional custom root directory for temporary page files during a scan session.
  /// Defaults to an isolated subfolder inside `getTemporaryDirectory()`.
  final String? workingDirectoryPath;

  /// Creates a modified copy of this [CustomScannerConfig].
  CustomScannerConfig copyWith({
    CaptureConfig? capture,
    ProcessingConfig? processing,
    PageListConfig? pageList,
    PdfConfig? pdf,
    ScannerUiConfig? ui,
    String? workingDirectoryPath,
  }) => CustomScannerConfig(
    capture: capture ?? this.capture,
    processing: processing ?? this.processing,
    pageList: pageList ?? this.pageList,
    pdf: pdf ?? this.pdf,
    ui: ui ?? this.ui,
    workingDirectoryPath: workingDirectoryPath ?? this.workingDirectoryPath,
  );
}
