import 'crop_corners.dart';

/// Origin of a page's crop boundary.
enum CropSource {
  /// Automatically detected by OpenCV contour/Otsu detection.
  auto,

  /// Adjusted by the user in the interactive 4-corner crop editor.
  manual,

  /// Returned pre-cropped by a native scanner (such as ML Kit Document Scanner).
  preCropped,

  /// Uses the full uncropped image frame.
  fullImage;

  /// Parses [name] into a [CropSource].
  static CropSource fromName(String? name) => CropSource.values.firstWhere(
    (s) => s.name == name,
    orElse: () => CropSource.fullImage,
  );
}

/// Validation issue identified during automatic or manual corner selection.
enum CropIssue {
  /// No plausible four-corner document contour was found.
  noCorners,

  /// Candidate contour scored below `minCropConfidence`.
  lowConfidence,

  /// Quadrilateral covers too little of the image area.
  tooSmall,

  /// Quadrilateral is concave or self-intersecting.
  notConvex,

  /// At least one interior corner angle is unrealistically acute.
  sharpAngle,

  /// Crop edge lies directly on the camera frame border.
  touchesFrameEdge,
}

/// Result of running document boundary detection on an image or preview frame.
class DetectionResult {
  /// Creates a [DetectionResult].
  const DetectionResult({
    required this.corners,
    required this.confidence,
    required this.imageWidth,
    required this.imageHeight,
    this.issues = const [],
  });

  /// Creates an empty detection result when no document candidate was found.
  const DetectionResult.none({
    required this.imageWidth,
    required this.imageHeight,
  }) : corners = null,
       confidence = 0,
       issues = const [CropIssue.noCorners];

  /// Detected corners in oriented image pixel coordinates, if any.
  final CropCorners? corners;

  /// Confidence score in `[0.0, 1.0]`.
  final double confidence;

  /// Width of the analyzed source image in pixels.
  final int imageWidth;

  /// Height of the analyzed source image in pixels.
  final int imageHeight;

  /// Any validation issues flagged for [corners].
  final List<CropIssue> issues;

  /// True when [corners] is present and [issues] is empty.
  bool get isConfident => corners != null && issues.isEmpty;
}

/// Result of writing a perspective-cropped image to disk.
class CropResult {
  /// Creates a [CropResult].
  const CropResult({
    required this.path,
    required this.corners,
    required this.source,
    required this.width,
    required this.height,
    this.confidence,
  });

  /// File path of the written cropped JPEG.
  final String path;

  /// Corners in source-image pixel space that produced this crop.
  final CropCorners corners;

  /// How the crop corners were determined.
  final CropSource source;

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// Optional detector confidence (`0.0..1.0`).
  final double? confidence;
}
