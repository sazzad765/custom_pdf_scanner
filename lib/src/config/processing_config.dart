import 'package:flutter/foundation.dart';

import '../domain/page_quality.dart';
import '../domain/scan_filter.dart';

/// Ready-made resolution and compression presets for OpenCV processing.
enum ScanQualityPreset {
  /// Smaller files (~1700 px long edge, JPEG quality 78) — ideal for mobile
  /// email/messaging attachments.
  compact,

  /// Sharp text with moderate file size (~2400 px long edge, JPEG quality 86) —
  /// recommended default (~200 DPI on A4).
  balanced,

  /// Full native sensor resolution (`maxLongEdge: 0`, JPEG quality 95) — ideal
  /// for archival, OCR, and fine print.
  high,
}

/// Complete configuration for OpenCV document detection, perspective cropping,
/// filter enhancement, thumbnailing, and quality analysis.
@immutable
class ProcessingConfig {
  /// Creates a [ProcessingConfig] with granular control over every OpenCV stage.
  const ProcessingConfig({
    this.defaultFilter = ScanFilter.magicColor,
    this.availableFilters = const [
      ScanFilter.magicColor,
      ScanFilter.natural,
      ScanFilter.grayscale,
      ScanFilter.blackAndWhite,
      ScanFilter.original,
    ],
    this.autoCrop = true,
    this.cropSafetyMargin = 0.008,
    this.detectionAnalysisEdge = 640,
    this.minAreaRatio = 0.18,
    this.maxAreaRatio = 0.985,
    this.minContrast = 12.0,
    this.minCropConfidence = 0.55,
    this.minCornerAngle = 50.0,
    this.openManualCropOnLowConfidence = false,
    this.maxLongEdge = 2400,
    this.jpegQuality = 86,
    this.croppedJpegQuality = 92,
    this.pngCompression = 3,
    this.thumbnailEdge = 240,
    this.thumbnailQuality = 72,
    this.backgroundEstimateEdge = 640,
    this.backgroundKernelDivisor = 18,
    this.backgroundBlurDivisor = 6,
    this.paperKnee = 0.82,
    this.backgroundKnee = 0.78,
    this.paperWhitePoint = 0.98,
    this.paperWhiteMargin = 0.97,
    this.inkFloor = 0.06,
    this.speckleRemoval = true,
    this.speckleAreaFraction = 1.2e-6,
    this.minSpeckleArea = 4,
    this.maxSpeckleArea = 16,
    this.faintSpeckleLevel = 190,
    this.maxFaintSpeckleArea = 20,
    this.inkMaskLevel = 190,
    this.claheClipLimit = 1.4,
    this.claheContrastTrigger = 46.0,
    this.sharpenAmount = 0.5,
    this.sharpenRadiusMin = 0.6,
    this.sharpenRadiusMax = 1.0,
    this.denoise = false,
    this.denoiseStrength = 7,
    this.noiseTrigger = 3.5,
    this.coloredPaperSaturationTrigger = 26.0,
    this.coloredPaperLightnessBlend = 0.88,
    this.coloredPaperInkStrength = 0.42,
    this.coloredPaperContrastFloor = 5,
    this.coloredPaperContrastCeiling = 20,
    this.colorArtworkDeviationTrigger = 28.0,
    this.colorArtworkFractionTrigger = 0.08,
    this.colorArtworkSaturationBoost = 1.55,
    this.tintedPaperSaturationBoost = 1.12,
    this.tintedBackgroundEdge = 1200,
    this.backgroundRefinement = true,
    this.residualShadowRemoval = true,
    this.foregroundDarkLevel = 232,
    this.foregroundEdgeLevel = 10,
    this.foregroundGuard = 3,
    this.residualShadowEdge = 320,
    this.maxResidualLift = 28,
    this.minCoverage = 32,
    this.blackWhiteWindowDivisor = 32,
    this.blackWhiteStatsEdge = 1600,
    this.blackWhiteMinWindow = 25,
    this.blackWhiteMaxWindow = 101,
    this.blackWhiteSauvolaK = 0.12,
    this.blackWhiteDynamicRange = 128.0,
    this.enableQualityChecks = true,
    this.qualityAnalysisEdge = 1200,
    this.qualityThresholds = const QualityThresholds(),
    this.useIsolate = true,
  });

  /// Creates a configuration from a [ScanQualityPreset].
  factory ProcessingConfig.fromPreset(
    ScanQualityPreset preset, {
    ScanFilter defaultFilter = ScanFilter.magicColor,
    bool useIsolate = true,
  }) => switch (preset) {
    ScanQualityPreset.compact => ProcessingConfig(
      defaultFilter: defaultFilter,
      maxLongEdge: 1700,
      jpegQuality: 78,
      useIsolate: useIsolate,
    ),
    ScanQualityPreset.balanced => ProcessingConfig(
      defaultFilter: defaultFilter,
      maxLongEdge: 2400,
      jpegQuality: 86,
      useIsolate: useIsolate,
    ),
    ScanQualityPreset.high => ProcessingConfig(
      defaultFilter: defaultFilter,
      maxLongEdge: 0,
      jpegQuality: 95,
      croppedJpegQuality: 96,
      useIsolate: useIsolate,
    ),
  };

  /// Filter applied automatically to newly captured/imported pages.
  final ScanFilter defaultFilter;

  /// Filters exposed in the page editor and batch-filter picker.
  final List<ScanFilter> availableFilters;

  /// Runs OpenCV quadrilateral edge detection + perspective warp on uncropped inputs.
  final bool autoCrop;

  /// Outward safety margin added around auto-detected page corners (`0.008` ≈ 2 mm on A4).
  final double cropSafetyMargin;

  /// Long edge in pixels used during OpenCV quad corner search.
  final int detectionAnalysisEdge;

  /// Minimum fraction of the frame a detected page must occupy.
  final double minAreaRatio;

  /// Maximum fraction of the frame before a contour is treated as the frame border.
  final double maxAreaRatio;

  /// Minimum greyscale contrast between inside and outside of a candidate page quad.
  final double minContrast;

  /// Minimum detector confidence (`0..1`) required to trust an auto-crop without warning.
  final double minCropConfidence;

  /// Minimum interior corner angle (degrees) for automatic quad detection.
  final double minCornerAngle;

  /// Opens the interactive manual crop screen automatically during single-page
  /// review when auto-crop confidence is low.
  final bool openManualCropOnLowConfidence;

  /// Maximum long edge in pixels (`0` preserves full sensor resolution).
  final int maxLongEdge;

  /// JPEG quality (`1..100`) for enhanced color and grayscale output.
  final int jpegQuality;

  /// JPEG quality (`1..100`) for the intermediate perspective-cropped source image.
  final int croppedJpegQuality;

  /// PNG zlib compression level (`0..9`) for `ScanFilter.blackAndWhite`.
  final int pngCompression;

  /// Long edge in pixels for list/grid thumbnails.
  final int thumbnailEdge;

  /// JPEG quality (`1..100`) for list/grid thumbnails.
  final int thumbnailQuality;

  // --- OpenCV Enhancement Tuning ---

  /// Long edge in pixels used to estimate uneven page illumination.
  final int backgroundEstimateEdge;

  /// Morphological closing kernel divisor (`shortEdge ~/ divisor`).
  final int backgroundKernelDivisor;

  /// Gaussian blur divisor (`shortEdge ~/ divisor`) for background estimation.
  final int backgroundBlurDivisor;

  /// Tone-curve knee (`0..1`) for content-protected paper whitening.
  final double paperKnee;

  /// Stronger tone-curve knee (`0..1`) applied outside foreground ink masks.
  final double backgroundKnee;

  /// White-point ceiling (`0..1`) for paper whitening.
  final double paperWhitePoint;

  /// Multiplier (`0..1`) applied to measured paper brightness for the white point.
  final double paperWhiteMargin;

  /// Darkest ink floor (`0..1`) kept untouched by whitening curves.
  final double inkFloor;

  /// Removes isolated tiny background dust/speckles while preserving punctuation.
  final bool speckleRemoval;

  /// Speckle area ceiling as a fraction of total page pixels.
  final double speckleAreaFraction;

  /// Minimum speckle ceiling in pixels.
  final int minSpeckleArea;

  /// Maximum dark speckle ceiling in pixels.
  final int maxSpeckleArea;

  /// Grey level above which a tiny speck is treated as faint paper noise.
  final int faintSpeckleLevel;

  /// Maximum area in pixels for faint paper-noise specks.
  final int maxFaintSpeckleArea;

  /// Grey threshold (`0..255`) used to locate candidate ink components.
  final int inkMaskLevel;

  /// CLAHE clip limit applied on Lab lightness when contrast is low.
  final double claheClipLimit;

  /// Page contrast threshold below which CLAHE is triggered.
  final double claheContrastTrigger;

  /// Unsharp mask strength (`0` disables sharpening).
  final double sharpenAmount;

  /// Minimum Gaussian sigma for unsharp masking.
  final double sharpenRadiusMin;

  /// Maximum Gaussian sigma for unsharp masking.
  final double sharpenRadiusMax;

  /// Enables bilateral denoising when measured sensor noise exceeds [noiseTrigger].
  final bool denoise;

  /// Bilateral filter sigma for denoising.
  final int denoiseStrength;

  /// Residual noise floor above which [denoise] activates.
  final double noiseTrigger;

  /// Mean HSV saturation threshold above which a sheet is treated as colored/aged paper.
  final double coloredPaperSaturationTrigger;

  /// Blend weight (`0..1`) of illumination-flattened lightness on colored sheets.
  final double coloredPaperLightnessBlend;

  /// Ink-darkening strength (`0..0.75`) on colored/aged sheets.
  final double coloredPaperInkStrength;

  /// Local contrast floor on colored sheets.
  final int coloredPaperContrastFloor;

  /// Local contrast ceiling on colored sheets.
  final int coloredPaperContrastCeiling;

  /// Saturation std-dev trigger for multi-color covers, stamps, and forms.
  final double colorArtworkDeviationTrigger;

  /// Minimum fraction of strongly colored pixels to trigger artwork mode.
  final double colorArtworkFractionTrigger;

  /// Saturation LUT gain on multi-color artwork pages.
  final double colorArtworkSaturationBoost;

  /// Gentle saturation LUT gain on tinted/aged sheets.
  final double tintedPaperSaturationBoost;

  /// Long edge in pixels for bilateral background smoothing on tinted/artwork sheets.
  final int tintedBackgroundEdge;

  /// Enables foreground mask protection during paper whitening.
  final bool backgroundRefinement;

  /// Enables bounded additive lift of residual shadows outside foreground ink.
  final bool residualShadowRemoval;

  /// Grey threshold (`0..255`) below which pixels are protected as dark ink.
  final int foregroundDarkLevel;

  /// Morphological gradient threshold (`0..255`) protected as stroke edges.
  final int foregroundEdgeLevel;

  /// Dilation guard radius in pixels around foreground ink/edges.
  final int foregroundGuard;

  /// Long edge in pixels used for residual shadow field estimation.
  final int residualShadowEdge;

  /// Maximum additive greyscale levels (`0..255`) added by residual shadow lift.
  final int maxResidualLift;

  /// Minimum background coverage required for full residual shadow lift.
  final int minCoverage;

  /// Sauvola adaptive window divisor (`shortEdge / divisor`).
  final int blackWhiteWindowDivisor;

  /// Long edge cap used to compute Sauvola local mean/variance efficiently.
  final int blackWhiteStatsEdge;

  /// Minimum odd window size for Sauvola thresholding.
  final int blackWhiteMinWindow;

  /// Maximum odd window size for Sauvola thresholding.
  final int blackWhiteMaxWindow;

  /// Sauvola sensitivity parameter `k` (typically `0.10..0.20`).
  final double blackWhiteSauvolaK;

  /// Sauvola dynamic range `R` (typically `128.0`).
  final double blackWhiteDynamicRange;

  /// Runs advisory blur, glare, exposure, and output validation checks.
  final bool enableQualityChecks;

  /// Long edge in pixels used for capture sharpness/glare measurement.
  final int qualityAnalysisEdge;

  /// Numeric thresholds for advisory quality warnings.
  final QualityThresholds qualityThresholds;

  /// Executes heavy OpenCV operations inside `Isolate.run` so UI stays 60fps.
  final bool useIsolate;

  /// Creates a modified copy of this [ProcessingConfig].
  ProcessingConfig copyWith({
    ScanFilter? defaultFilter,
    List<ScanFilter>? availableFilters,
    bool? autoCrop,
    double? cropSafetyMargin,
    int? detectionAnalysisEdge,
    double? minAreaRatio,
    double? maxAreaRatio,
    double? minContrast,
    double? minCropConfidence,
    double? minCornerAngle,
    bool? openManualCropOnLowConfidence,
    int? maxLongEdge,
    int? jpegQuality,
    int? croppedJpegQuality,
    int? pngCompression,
    int? thumbnailEdge,
    int? thumbnailQuality,
    double? paperKnee,
    double? backgroundKnee,
    double? paperWhitePoint,
    double? paperWhiteMargin,
    double? inkFloor,
    bool? speckleRemoval,
    double? claheClipLimit,
    double? sharpenAmount,
    bool? denoise,
    int? denoiseStrength,
    bool? backgroundRefinement,
    bool? residualShadowRemoval,
    double? blackWhiteSauvolaK,
    int? blackWhiteWindowDivisor,
    bool? enableQualityChecks,
    QualityThresholds? qualityThresholds,
    bool? useIsolate,
  }) => ProcessingConfig(
    defaultFilter: defaultFilter ?? this.defaultFilter,
    availableFilters: availableFilters ?? this.availableFilters,
    autoCrop: autoCrop ?? this.autoCrop,
    cropSafetyMargin: cropSafetyMargin ?? this.cropSafetyMargin,
    detectionAnalysisEdge: detectionAnalysisEdge ?? this.detectionAnalysisEdge,
    minAreaRatio: minAreaRatio ?? this.minAreaRatio,
    maxAreaRatio: maxAreaRatio ?? this.maxAreaRatio,
    minContrast: minContrast ?? this.minContrast,
    minCropConfidence: minCropConfidence ?? this.minCropConfidence,
    minCornerAngle: minCornerAngle ?? this.minCornerAngle,
    openManualCropOnLowConfidence:
        openManualCropOnLowConfidence ?? this.openManualCropOnLowConfidence,
    maxLongEdge: maxLongEdge ?? this.maxLongEdge,
    jpegQuality: jpegQuality ?? this.jpegQuality,
    croppedJpegQuality: croppedJpegQuality ?? this.croppedJpegQuality,
    pngCompression: pngCompression ?? this.pngCompression,
    thumbnailEdge: thumbnailEdge ?? this.thumbnailEdge,
    thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
    backgroundEstimateEdge: backgroundEstimateEdge,
    backgroundKernelDivisor: backgroundKernelDivisor,
    backgroundBlurDivisor: backgroundBlurDivisor,
    paperKnee: paperKnee ?? this.paperKnee,
    backgroundKnee: backgroundKnee ?? this.backgroundKnee,
    paperWhitePoint: paperWhitePoint ?? this.paperWhitePoint,
    paperWhiteMargin: paperWhiteMargin ?? this.paperWhiteMargin,
    inkFloor: inkFloor ?? this.inkFloor,
    speckleRemoval: speckleRemoval ?? this.speckleRemoval,
    speckleAreaFraction: speckleAreaFraction,
    minSpeckleArea: minSpeckleArea,
    maxSpeckleArea: maxSpeckleArea,
    faintSpeckleLevel: faintSpeckleLevel,
    maxFaintSpeckleArea: maxFaintSpeckleArea,
    inkMaskLevel: inkMaskLevel,
    claheClipLimit: claheClipLimit ?? this.claheClipLimit,
    claheContrastTrigger: claheContrastTrigger,
    sharpenAmount: sharpenAmount ?? this.sharpenAmount,
    sharpenRadiusMin: sharpenRadiusMin,
    sharpenRadiusMax: sharpenRadiusMax,
    denoise: denoise ?? this.denoise,
    denoiseStrength: denoiseStrength ?? this.denoiseStrength,
    noiseTrigger: noiseTrigger,
    coloredPaperSaturationTrigger: coloredPaperSaturationTrigger,
    coloredPaperLightnessBlend: coloredPaperLightnessBlend,
    coloredPaperInkStrength: coloredPaperInkStrength,
    coloredPaperContrastFloor: coloredPaperContrastFloor,
    coloredPaperContrastCeiling: coloredPaperContrastCeiling,
    colorArtworkDeviationTrigger: colorArtworkDeviationTrigger,
    colorArtworkFractionTrigger: colorArtworkFractionTrigger,
    colorArtworkSaturationBoost: colorArtworkSaturationBoost,
    tintedPaperSaturationBoost: tintedPaperSaturationBoost,
    tintedBackgroundEdge: tintedBackgroundEdge,
    backgroundRefinement: backgroundRefinement ?? this.backgroundRefinement,
    residualShadowRemoval: residualShadowRemoval ?? this.residualShadowRemoval,
    foregroundDarkLevel: foregroundDarkLevel,
    foregroundEdgeLevel: foregroundEdgeLevel,
    foregroundGuard: foregroundGuard,
    residualShadowEdge: residualShadowEdge,
    maxResidualLift: maxResidualLift,
    minCoverage: minCoverage,
    blackWhiteWindowDivisor:
        blackWhiteWindowDivisor ?? this.blackWhiteWindowDivisor,
    blackWhiteStatsEdge: blackWhiteStatsEdge,
    blackWhiteMinWindow: blackWhiteMinWindow,
    blackWhiteMaxWindow: blackWhiteMaxWindow,
    blackWhiteSauvolaK: blackWhiteSauvolaK ?? this.blackWhiteSauvolaK,
    blackWhiteDynamicRange: blackWhiteDynamicRange,
    enableQualityChecks: enableQualityChecks ?? this.enableQualityChecks,
    qualityAnalysisEdge: qualityAnalysisEdge,
    qualityThresholds: qualityThresholds ?? this.qualityThresholds,
    useIsolate: useIsolate ?? this.useIsolate,
  );
}
