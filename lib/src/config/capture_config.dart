/// Whether a capture session scans a single page or multiple pages at once.
enum ScanMode {
  /// Captures a single page (`pageLimit: 1`).
  singlePage,

  /// Captures multiple pages in one batch, processes all captured pages through
  /// OpenCV, and appends them to the local reorderable page list.
  multiPage,
}

/// Post-capture flow when [CaptureConfig.scanMode] is [ScanMode.singlePage].
enum SinglePageBehavior {
  /// Auto-crops, enhances with `defaultFilter`, immediately builds the 1-page
  /// PDF, and returns `ScannedPdfResult` with zero extra taps.
  immediatePdf,

  /// Opens the single-page editor (filter, rotate, manual crop) and generates
  /// the 1-page PDF as soon as the user confirms.
  reviewThenPdf,

  /// Appends the single scanned page into the local reorderable page list,
  /// allowing the user to inspect, reorder, or tap "+ Add More" one-by-one.
  addToPageList,
}

/// Camera / scanner implementation used to acquire raw document images.
enum CaptureBackend {
  /// Uses Google ML Kit Document Scanner (Base mode, no ML filters) on Android
  /// and automatically uses the built-in Flutter Camera + live OpenCV boundary
  /// detector on iOS (and as fallback).
  auto,

  /// Forces Google ML Kit Document Scanner (Android only; supports both single
  /// and multi-page native scanning).
  mlKit,

  /// Forces the built-in Flutter Camera with live OpenCV edge overlay, torch,
  /// auto-capture, and multi-shot counter on both Android and iOS.
  customCamera,
}

/// Sensor resolution preset for [CaptureBackend.customCamera].
enum ScannerCameraResolution {
  /// ~480p–720p (fast, low-res).
  medium,

  /// ~720p–1080p.
  high,

  /// ~1080p–2K.
  veryHigh,

  /// ~4K (2160p).
  ultraHigh,

  /// Full native camera sensor resolution (recommended for crisp document text).
  max,
}

/// Configuration for page acquisition (single vs. multi-page, backend, camera
/// controls, and auto-capture).
class CaptureConfig {
  /// Creates a [CaptureConfig].
  const CaptureConfig({
    this.scanMode = ScanMode.multiPage,
    this.singlePageBehavior = SinglePageBehavior.reviewThenPdf,
    this.backend = CaptureBackend.auto,
    this.maxPages = 200,
    this.allowGalleryImport = true,
    this.enableTorch = true,
    this.initialTorchOn = false,
    this.autoCaptureOnStableEdge = true,
    this.autoCaptureStableFrames = 4,
    this.autoCaptureTolerance = 0.02,
    this.lowLightThreshold = 60.0,
    this.analysisInterval = const Duration(milliseconds: 220),
    this.previewAnalysisEdge = 480,
    this.cameraResolution = ScannerCameraResolution.max,
  });

  /// Single-page or multi-page capture mode.
  final ScanMode scanMode;

  /// Behavior after capturing a page in [ScanMode.singlePage].
  final SinglePageBehavior singlePageBehavior;

  /// Native ML Kit vs. built-in OpenCV camera backend.
  final CaptureBackend backend;

  /// Maximum total pages allowed in the session (`null` for unlimited).
  ///
  /// When [scanMode] is [ScanMode.singlePage] and [singlePageBehavior] is not
  /// [SinglePageBehavior.addToPageList], capture is automatically capped to 1.
  final int? maxPages;

  /// Allows importing existing photos from the gallery inside ML Kit scanner.
  final bool allowGalleryImport;

  /// Shows the flashlight/torch toggle in [CaptureBackend.customCamera].
  final bool enableTorch;

  /// Starts the camera with the torch turned on when supported.
  final bool initialTorchOn;

  /// Enables automatic shutter firing when a page quad stays steady in
  /// [CaptureBackend.customCamera].
  final bool autoCaptureOnStableEdge;

  /// Consecutive stable preview frames required before auto-capture fires.
  final int autoCaptureStableFrames;

  /// Maximum normalized corner movement (`0..1`) considered stationary.
  final double autoCaptureTolerance;

  /// Mean luma (`0..255`) below which low-light warning suppresses auto-capture.
  final double lowLightThreshold;

  /// Minimum interval between OpenCV preview-frame boundary detections.
  final Duration analysisInterval;

  /// Long edge in pixels to which camera preview frames are subsampled.
  final int previewAnalysisEdge;

  /// Camera sensor resolution preset for [CaptureBackend.customCamera].
  final ScannerCameraResolution cameraResolution;

  /// Creates a modified copy of this [CaptureConfig].
  CaptureConfig copyWith({
    ScanMode? scanMode,
    SinglePageBehavior? singlePageBehavior,
    CaptureBackend? backend,
    int? maxPages,
    bool clearMaxPages = false,
    bool? allowGalleryImport,
    bool? enableTorch,
    bool? initialTorchOn,
    bool? autoCaptureOnStableEdge,
    int? autoCaptureStableFrames,
    double? autoCaptureTolerance,
    double? lowLightThreshold,
    Duration? analysisInterval,
    int? previewAnalysisEdge,
    ScannerCameraResolution? cameraResolution,
  }) => CaptureConfig(
    scanMode: scanMode ?? this.scanMode,
    singlePageBehavior: singlePageBehavior ?? this.singlePageBehavior,
    backend: backend ?? this.backend,
    maxPages: clearMaxPages ? null : (maxPages ?? this.maxPages),
    allowGalleryImport: allowGalleryImport ?? this.allowGalleryImport,
    enableTorch: enableTorch ?? this.enableTorch,
    initialTorchOn: initialTorchOn ?? this.initialTorchOn,
    autoCaptureOnStableEdge:
        autoCaptureOnStableEdge ?? this.autoCaptureOnStableEdge,
    autoCaptureStableFrames:
        autoCaptureStableFrames ?? this.autoCaptureStableFrames,
    autoCaptureTolerance: autoCaptureTolerance ?? this.autoCaptureTolerance,
    lowLightThreshold: lowLightThreshold ?? this.lowLightThreshold,
    analysisInterval: analysisInterval ?? this.analysisInterval,
    previewAnalysisEdge: previewAnalysisEdge ?? this.previewAnalysisEdge,
    cameraResolution: cameraResolution ?? this.cameraResolution,
  );
}
