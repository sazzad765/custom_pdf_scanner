import 'crop_corners.dart';
import 'crop_models.dart';
import 'page_quality.dart';
import 'scan_filter.dart';

/// Immutable metadata and local disk paths for one scanned page in the
/// reorderable page list.
///
/// Image bytes are never kept in memory on [ScannedPage]; all paths point to
/// files inside the local scan workspace so hundreds of pages can be held and
/// reordered smoothly.
class ScannedPage {
  /// Creates a [ScannedPage].
  const ScannedPage({
    required this.id,
    required this.pageNumber,
    required this.originalPath,
    required this.croppedPath,
    required this.processedPath,
    required this.capturedAt,
    this.thumbnailPath,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.width = 0,
    this.height = 0,
    this.corners,
    this.cropSource = CropSource.auto,
    this.cropConfidence,
    this.rotationQuarterTurns = 0,
    this.filter = ScanFilter.magicColor,
    this.quality = PageQuality.clean,
    this.usedFallback = false,
    this.checksum,
    this.byteLength,
  });

  /// Stable unique identifier for this page.
  final String id;

  /// 1-based position in the current document order (updated automatically on reorder).
  final int pageNumber;

  /// Absolute path to the raw captured/imported image file.
  final String originalPath;

  /// Absolute path to the perspective-cropped upright JPEG.
  final String croppedPath;

  /// Absolute path to the OpenCV-enhanced output file (`.jpg` or `.png`).
  final String processedPath;

  /// Absolute path to the compact thumbnail JPEG used in reorderable lists/grids.
  final String? thumbnailPath;

  /// Width of [originalPath] in pixels.
  final int originalWidth;

  /// Height of [originalPath] in pixels.
  final int originalHeight;

  /// Width of [exportPath] in pixels.
  final int width;

  /// Height of [exportPath] in pixels.
  final int height;

  /// Perspective crop quadrilateral in [originalPath] coordinates.
  final CropCorners? corners;

  /// How [corners] were obtained.
  final CropSource cropSource;

  /// Detector confidence score (`0.0..1.0`) when [cropSource] is [CropSource.auto].
  final double? cropConfidence;

  /// Clockwise 90-degree quarter turns (`0..3`) applied after perspective crop.
  final int rotationQuarterTurns;

  /// Currently active enhancement filter.
  final ScanFilter filter;

  /// Advisory quality report for this page.
  final PageQuality quality;

  /// True if OpenCV enhancement fell back to [croppedPath] due to an error.
  final bool usedFallback;

  /// Optional SHA-256 hex digest of [exportPath].
  final String? checksum;

  /// Size of [exportPath] in bytes.
  final int? byteLength;

  /// Timestamp when this page was captured or imported.
  final DateTime capturedAt;

  /// Full-resolution image path to display in previews and embed in the PDF.
  String get exportPath =>
      filter == ScanFilter.original ? croppedPath : processedPath;

  /// Best path for list/grid thumbnails (falls back to [exportPath]).
  String get listPreviewPath => thumbnailPath ?? exportPath;

  /// Creates a modified copy of this [ScannedPage].
  ScannedPage copyWith({
    int? pageNumber,
    String? originalPath,
    String? croppedPath,
    String? processedPath,
    String? thumbnailPath,
    int? originalWidth,
    int? originalHeight,
    int? width,
    int? height,
    CropCorners? corners,
    CropSource? cropSource,
    double? cropConfidence,
    int? rotationQuarterTurns,
    ScanFilter? filter,
    PageQuality? quality,
    bool? usedFallback,
    String? checksum,
    int? byteLength,
  }) => ScannedPage(
    id: id,
    pageNumber: pageNumber ?? this.pageNumber,
    originalPath: originalPath ?? this.originalPath,
    croppedPath: croppedPath ?? this.croppedPath,
    processedPath: processedPath ?? this.processedPath,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    originalWidth: originalWidth ?? this.originalWidth,
    originalHeight: originalHeight ?? this.originalHeight,
    width: width ?? this.width,
    height: height ?? this.height,
    corners: corners ?? this.corners,
    cropSource: cropSource ?? this.cropSource,
    cropConfidence: cropConfidence ?? this.cropConfidence,
    rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
    filter: filter ?? this.filter,
    quality: quality ?? this.quality,
    usedFallback: usedFallback ?? this.usedFallback,
    checksum: checksum ?? this.checksum,
    byteLength: byteLength ?? this.byteLength,
    capturedAt: capturedAt,
  );
}

/// Live progress emitted while OpenCV processes a multi-page capture batch.
class BatchProcessingProgress {
  /// Creates a [BatchProcessingProgress] snapshot.
  const BatchProcessingProgress({
    required this.completed,
    required this.total,
    this.currentIndex = 0,
    this.latestPage,
  });

  /// Number of pages in the current batch that have finished OpenCV processing.
  final int completed;

  /// Total number of pages in the current batch.
  final int total;

  /// 1-based index of the page currently being processed.
  final int currentIndex;

  /// Most recently completed [ScannedPage], if any.
  final ScannedPage? latestPage;

  /// Completion fraction in `[0.0, 1.0]`.
  double get fraction => total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);
}
