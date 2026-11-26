import 'package:flutter/painting.dart';

/// Target PDF page dimensions in PDF points (`1 pt = 1 / 72 inch`).
class PdfPageSize {
  const PdfPageSize._(this.name, this.widthPt, this.heightPt);

  /// Creates a custom fixed PDF page size in points (`72 points = 1 inch`).
  const PdfPageSize.custom({
    required double widthPt,
    required double heightPt,
    String name = 'custom',
  }) : this._(name, widthPt, heightPt);

  /// Sizes each PDF page dynamically to match its scanned image's aspect ratio
  /// at [PdfConfig.dpi].
  static const fitToImage = PdfPageSize._('fitToImage', 0, 0);

  /// ISO A4 (`210 × 297 mm` / `595.28 × 841.89 pt`).
  static const a4 = PdfPageSize._('a4', 595.28, 841.89);

  /// US Letter (`8.5 × 11 in` / `612 × 792 pt`).
  static const letter = PdfPageSize._('letter', 612.0, 792.0);

  /// US Legal (`8.5 × 14 in` / `612 × 1008 pt`).
  static const legal = PdfPageSize._('legal', 612.0, 1008.0);

  /// Identifier for debugging/serialization.
  final String name;

  /// Page width in PDF points (`0` when [isFitToImage]).
  final double widthPt;

  /// Page height in PDF points (`0` when [isFitToImage]).
  final double heightPt;

  /// True when each page matches its underlying image dimensions.
  bool get isFitToImage => widthPt <= 0 || heightPt <= 0;
}

/// Orientation rule for fixed PDF page sizes (`A4`, `Letter`, `Legal`, `custom`).
enum PdfPageOrientation {
  /// Rotates the page box to landscape when the scanned image is wider than tall,
  /// and portrait otherwise.
  auto,

  /// Always keeps the fixed page box in portrait orientation.
  portrait,

  /// Always keeps the fixed page box in landscape orientation.
  landscape,
}

/// How a scanned page image is fitted inside the target PDF content box.
enum PdfImageFit {
  /// Scales uniformly so the entire scanned page fits inside margins without cropping.
  contain,

  /// Scales uniformly to fill the entire content box (cropping overflow).
  cover,

  /// Stretches to fill both width and height of the content box.
  fill,
}

/// Standard PDF document `/Info` dictionary metadata.
class PdfDocumentMetadata {
  /// Creates [PdfDocumentMetadata].
  const PdfDocumentMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator = 'custom_pdf_scanner',
    this.producer = 'custom_pdf_scanner (Local Streaming PDF Engine)',
  });

  /// Document `/Title`.
  final String? title;

  /// Document `/Author`.
  final String? author;

  /// Document `/Subject`.
  final String? subject;

  /// Document `/Keywords`.
  final String? keywords;

  /// Document `/Creator` application name.
  final String creator;

  /// Document `/Producer` engine string.
  final String producer;
}

/// Configuration for local on-device PDF generation.
class PdfConfig {
  /// Creates a [PdfConfig].
  const PdfConfig({
    this.outputDirectoryPath,
    this.customOutputFilePath,
    this.fileNamePrefix = 'scan_',
    this.pageSize = PdfPageSize.fitToImage,
    this.orientation = PdfPageOrientation.auto,
    this.marginsPt = EdgeInsets.zero,
    this.imageFit = PdfImageFit.contain,
    this.dpi = 150.0,
    this.metadata = const PdfDocumentMetadata(),
    this.computeSha256 = true,
    this.deleteTempFilesAfterExport = false,
    this.useIsolate = true,
  });

  /// Directory where generated PDFs are written when [customOutputFilePath] is null.
  /// Defaults to the platform temporary directory.
  final String? outputDirectoryPath;

  /// Exact file path where the generated `.pdf` should be saved. Overrides
  /// [outputDirectoryPath] and [fileNamePrefix] when provided.
  final String? customOutputFilePath;

  /// Prefix for auto-generated PDF filenames (e.g. `scan_1732601200000.pdf`).
  final String fileNamePrefix;

  /// PDF page size (`fitToImage`, `a4`, `letter`, `legal`, or `custom`).
  final PdfPageSize pageSize;

  /// Page orientation for fixed page sizes.
  final PdfPageOrientation orientation;

  /// Margins in PDF points (`72 pt = 1 inch`) around each page's image area.
  final EdgeInsets marginsPt;

  /// Image scaling mode within the printable page box.
  final PdfImageFit imageFit;

  /// Target dots-per-inch used to size `PdfPageSize.fitToImage` pages (`72 / dpi` pt per pixel).
  final double dpi;

  /// Embedded PDF `/Info` metadata.
  final PdfDocumentMetadata metadata;

  /// Computes and returns the SHA-256 checksum of the final `.pdf` file.
  final bool computeSha256;

  /// Deletes temporary captured/cropped/processed page image files right after
  /// building the PDF. Leave `false` if your app also reads `result.pages[i].exportPath`.
  final bool deleteTempFilesAfterExport;

  /// Runs PDF stream assembly on a background isolate.
  final bool useIsolate;

  /// Creates a modified copy of this [PdfConfig].
  PdfConfig copyWith({
    String? outputDirectoryPath,
    String? customOutputFilePath,
    String? fileNamePrefix,
    PdfPageSize? pageSize,
    PdfPageOrientation? orientation,
    EdgeInsets? marginsPt,
    PdfImageFit? imageFit,
    double? dpi,
    PdfDocumentMetadata? metadata,
    bool? computeSha256,
    bool? deleteTempFilesAfterExport,
    bool? useIsolate,
  }) => PdfConfig(
    outputDirectoryPath: outputDirectoryPath ?? this.outputDirectoryPath,
    customOutputFilePath: customOutputFilePath ?? this.customOutputFilePath,
    fileNamePrefix: fileNamePrefix ?? this.fileNamePrefix,
    pageSize: pageSize ?? this.pageSize,
    orientation: orientation ?? this.orientation,
    marginsPt: marginsPt ?? this.marginsPt,
    imageFit: imageFit ?? this.imageFit,
    dpi: dpi ?? this.dpi,
    metadata: metadata ?? this.metadata,
    computeSha256: computeSha256 ?? this.computeSha256,
    deleteTempFilesAfterExport:
        deleteTempFilesAfterExport ?? this.deleteTempFilesAfterExport,
    useIsolate: useIsolate ?? this.useIsolate,
  );
}
