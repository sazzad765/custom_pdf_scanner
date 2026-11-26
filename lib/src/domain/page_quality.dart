/// Advisory quality verdict for a scanned page.
enum QualityDecision {
  /// No quality issues detected.
  pass,

  /// Advisory warning (e.g., glare, slight blur, grey background).
  warning,

  /// Strong recommendation to retake (e.g., severe blur or unreadable size).
  fail;

  /// Parses [name] into a [QualityDecision].
  static QualityDecision fromName(String? name) => QualityDecision.values
      .firstWhere((d) => d.name == name, orElse: () => QualityDecision.pass);

  /// Returns the more severe of `this` and [other].
  QualityDecision worst(QualityDecision other) =>
      index >= other.index ? this : other;
}

/// Specific pre- or post-processing quality check identifier.
enum QualityCheck {
  /// Out-of-focus capture (low Laplacian variance).
  blur,

  /// Directional camera motion blur.
  motion,

  /// Specular flash or lighting glare on the sheet.
  glare,

  /// Underexposed / dark capture.
  underexposed,

  /// Overexposed / washed-out capture.
  overexposed,

  /// Low pixel resolution on the cropped page's short edge.
  lowResolution,

  /// Auto-crop touches the camera frame edge.
  cropIncomplete,

  /// Processed output could not be decoded.
  undecodable,

  /// Processed output dimensions are invalid.
  invalidDimensions,

  /// Page appears blank or nearly uniform.
  blankPage,

  /// Enhancement may have removed faint ink strokes.
  textLost,

  /// Paper background remained noticeably grey after whitening.
  greyBackground,

  /// Dark regions lost detail due to shadow crushing.
  crushedDark,

  /// Foreground content may have clipped to white.
  clippedForeground,

  /// Enhanced output diverged strongly from the source image.
  divergentOutput,
}

/// Configurable numeric thresholds for advisory [PageQuality] evaluation.
class QualityThresholds {
  /// Creates [QualityThresholds] with production-tested defaults.
  const QualityThresholds({
    this.blurWarning = 60,
    this.blurFail = 20,
    this.motionRatio = 2.6,
    this.darkMean = 70,
    this.darkMeanFail = 40,
    this.brightMean = 238,
    this.brightStd = 18,
    this.glareCentre = 0.012,
    this.glareAny = 0.03,
    this.minShortEdge = 1000,
    this.minShortEdgeFail = 600,
    this.edgeMarginFraction = 0.008,
    this.blankStd = 5,
    this.inkKept = 0.35,
    this.greyPaper = 205,
    this.crushedBlack = 0.25,
    this.clippedWhite = 0.995,
    this.minCorrelation = 0.25,
  });

  /// Laplacian sharpness below which a blur warning is raised.
  final double blurWarning;

  /// Laplacian sharpness below which a blur fail advisory is raised.
  final double blurFail;

  /// Sobel X/Y directional ratio indicating motion blur.
  final double motionRatio;

  /// Mean luminance below which a dark-page warning is raised.
  final double darkMean;

  /// Mean luminance below which a dark-page fail advisory is raised.
  final double darkMeanFail;

  /// Mean luminance above which overexposure is checked.
  final double brightMean;

  /// Standard deviation ceiling paired with [brightMean] for overexposure.
  final double brightStd;

  /// Maximum fraction of central glare blobs before warning.
  final double glareCentre;

  /// Maximum fraction of page-wide glare blobs before warning.
  final double glareAny;

  /// Recommended minimum short edge in pixels.
  final double minShortEdge;

  /// Minimum short edge below which a fail advisory is raised.
  final double minShortEdgeFail;

  /// Frame-border margin fraction used to flag [QualityCheck.cropIncomplete].
  final double edgeMarginFraction;

  /// Standard deviation threshold for blank-page advisories.
  final double blankStd;

  /// Minimum output/input ink ratio before flagging [QualityCheck.textLost].
  final double inkKept;

  /// Minimum expected whitened paper level on neutral pages.
  final double greyPaper;

  /// Maximum dark-pixel share before flagging [QualityCheck.crushedDark].
  final double crushedBlack;

  /// Maximum bright-pixel share before flagging [QualityCheck.clippedForeground].
  final double clippedWhite;

  /// Minimum normalized cross-correlation between input and output thumbnails.
  final double minCorrelation;
}

/// Single advisory issue reported for a scanned page.
class QualityIssue {
  /// Creates a [QualityIssue].
  const QualityIssue({
    required this.check,
    required this.decision,
    required this.message,
  });

  /// Deserializes a [QualityIssue] from JSON.
  factory QualityIssue.fromJson(Map<String, Object?> json) => QualityIssue(
    check: QualityCheck.values.byName(json['check']! as String),
    decision: QualityDecision.fromName(json['decision'] as String?),
    message: json['message']! as String,
  );

  /// Which check triggered this issue.
  final QualityCheck check;

  /// Advisory severity.
  final QualityDecision decision;

  /// Human-readable recommendation.
  final String message;

  /// Serializes this issue to JSON.
  Map<String, Object?> toJson() => {
    'check': check.name,
    'decision': decision.name,
    'message': message,
  };
}

/// Aggregated advisory quality assessment and raw OpenCV metrics for one page.
class PageQuality {
  /// Creates a [PageQuality] report.
  const PageQuality({this.issues = const [], this.metrics = const {}});

  /// Deserializes a [PageQuality] from JSON.
  factory PageQuality.fromJson(Map<String, Object?> json) => PageQuality(
    issues: [
      for (final item in (json['issues'] as List<Object?>? ?? const []))
        QualityIssue.fromJson(item! as Map<String, Object?>),
    ],
    metrics: {
      for (final e
          in (json['metrics'] as Map<String, Object?>? ?? const {}).entries)
        e.key: (e.value! as num).toDouble(),
    },
  );

  /// Empty quality report with no issues.
  static const clean = PageQuality();

  /// Flagged advisory issues.
  final List<QualityIssue> issues;

  /// Raw numeric measurements (`sharpness`, `mean`, `glare_center`, etc.).
  final Map<String, double> metrics;

  /// Highest severity across [issues], or [QualityDecision.pass] if empty.
  QualityDecision get decision =>
      issues.fold(QualityDecision.pass, (d, i) => d.worst(i.decision));

  /// Highest-priority message suitable for a compact UI banner, or `null`.
  String? get headline {
    if (issues.isEmpty) return null;
    final sorted = [...issues]
      ..sort((a, b) => b.decision.index.compareTo(a.decision.index));
    return sorted.first.message;
  }

  /// Combines capture-stage and output-stage quality reports.
  PageQuality merge(PageQuality other) => PageQuality(
    issues: [...issues, ...other.issues],
    metrics: {...metrics, ...other.metrics},
  );

  /// Serializes this quality report to JSON.
  Map<String, Object?> toJson() => {
    'issues': [for (final i in issues) i.toJson()],
    'metrics': metrics,
  };
}
