import 'dart:io';

import 'scanned_page.dart';

/// Progress snapshot emitted while streaming pages into the local PDF file.
class PdfGenerationProgress {
  /// Creates a [PdfGenerationProgress] snapshot.
  const PdfGenerationProgress({
    required this.completedPages,
    required this.totalPages,
  });

  /// Pages written to the PDF stream so far.
  final int completedPages;

  /// Total pages being written.
  final int totalPages;

  /// Completion fraction in `[0.0, 1.0]`.
  double get fraction =>
      totalPages <= 0 ? 0 : (completedPages / totalPages).clamp(0.0, 1.0);
}

/// Final local output returned after scanning, processing, and generating a PDF.
class ScannedPdfResult {
  /// Creates a [ScannedPdfResult].
  const ScannedPdfResult({
    required this.pdfPath,
    required this.pages,
    required this.pageCount,
    required this.byteLength,
    required this.generatedAt,
    this.sha256,
  });

  /// Absolute local file path of the generated `.pdf` file.
  final String pdfPath;

  /// Convenience [File] handle for [pdfPath].
  File get pdfFile => File(pdfPath);

  /// Ordered [ScannedPage] items included in the PDF.
  ///
  /// Note: If `PdfConfig.deleteTempFilesAfterExport` was set to `true`, the
  /// intermediate image files referenced by [pages] will have been cleaned up.
  final List<ScannedPage> pages;

  /// Total number of pages in the generated PDF.
  final int pageCount;

  /// File size of [pdfPath] in bytes.
  final int byteLength;

  /// Optional lowercase hex SHA-256 digest of the generated PDF file.
  final String? sha256;

  /// Timestamp when PDF generation completed.
  final DateTime generatedAt;
}
