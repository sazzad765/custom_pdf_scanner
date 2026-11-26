import 'package:flutter/material.dart';

import '../config/capture_config.dart';
import '../config/custom_scanner_config.dart';
import '../config/page_list_config.dart';
import '../config/pdf_config.dart';
import '../config/processing_config.dart';
import '../config/scanner_ui_config.dart';
import '../controller/custom_scanner_controller.dart';
import '../domain/scanned_page.dart';
import '../domain/scanned_pdf_result.dart';
import 'screens/scanned_pages_screen.dart';

/// High-level entry points for launching the document scanner UI or running
/// headless local OpenCV + PDF batch pipelines.
abstract final class CustomPdfScanner {
  /// Launches the full scanner flow with [config] and returns a local
  /// [ScannedPdfResult] (or `null` if the user cancels).
  static Future<ScannedPdfResult?> scan(
    BuildContext context, {
    CustomScannerConfig config = const CustomScannerConfig(),
  }) {
    final controller = CustomScannerController(config: config);
    return Navigator.of(context).push<ScannedPdfResult>(
      MaterialPageRoute(
        builder: (_) => ScannedPagesScreen(
          controller: controller,
          autoLaunchCaptureOnOpen: true,
          disposeControllerOnExit: true,
        ),
      ),
    );
  }

  /// Convenience launcher configured specifically for **single-page** scanning.
  static Future<ScannedPdfResult?> scanSinglePage(
    BuildContext context, {
    SinglePageBehavior behavior = SinglePageBehavior.reviewThenPdf,
    CaptureBackend backend = CaptureBackend.auto,
    ProcessingConfig processing = const ProcessingConfig(),
    PdfConfig pdf = const PdfConfig(),
    ScannerUiConfig ui = const ScannerUiConfig(),
  }) => scan(
    context,
    config: CustomScannerConfig.singlePage(
      behavior: behavior,
      backend: backend,
      processing: processing,
      pdf: pdf,
      ui: ui,
    ),
  );

  /// Convenience launcher configured specifically for **multi-page** batch
  /// scanning with OpenCV batch enhancement, reorderable local page list, and
  /// "+ Add More".
  static Future<ScannedPdfResult?> scanMultiPage(
    BuildContext context, {
    int? maxPages = 200,
    CaptureBackend backend = CaptureBackend.auto,
    bool allowGalleryImport = true,
    ProcessingConfig processing = const ProcessingConfig(),
    PageListConfig pageList = const PageListConfig(),
    PdfConfig pdf = const PdfConfig(),
    ScannerUiConfig ui = const ScannerUiConfig(),
  }) => scan(
    context,
    config: CustomScannerConfig.multiPage(
      maxPages: maxPages,
      backend: backend,
      allowGalleryImport: allowGalleryImport,
      processing: processing,
      pageList: pageList,
      pdf: pdf,
      ui: ui,
    ),
  );

  /// Pure **headless** batch pipeline: takes `1..N` local [imagePaths], runs
  /// OpenCV perspective crop + filter enhancement sequentially on each page,
  /// streams them into a local `.pdf` file, and returns [ScannedPdfResult].
  static Future<ScannedPdfResult> processFilesToPdf({
    required List<String> imagePaths,
    String? outputFilePath,
    bool preCropped = false,
    CustomScannerConfig config = const CustomScannerConfig(),
    void Function(BatchProcessingProgress progress)? onProcessingProgress,
    void Function(PdfGenerationProgress progress)? onPdfProgress,
  }) async {
    final controller = CustomScannerController(config: config);
    void listener() {
      if (controller.batchProgress != null) {
        onProcessingProgress?.call(controller.batchProgress!);
      }
      if (controller.pdfProgress != null) {
        onPdfProgress?.call(controller.pdfProgress!);
      }
    }

    controller.addListener(listener);
    try {
      await controller.addImageFiles(imagePaths, preCropped: preCropped);
      return await controller.generatePdf(outputFilePath: outputFilePath);
    } finally {
      controller.removeListener(listener);
      await controller.disposeWorkspaceAndController(
        deleteTempFiles: config.pdf.deleteTempFilesAfterExport,
      );
    }
  }
}
