import 'pdf_config.dart';

/// Which sides of an ID / NID card are required during `ScanMode.nidCard`.
enum NidScanSides {
  /// Scans both the **Front** and **Back** sides of the ID card (default).
  frontAndBack,

  /// Scans only the **Front** side of the ID card.
  frontOnly,
}

/// How Front and Back NID card images are arranged in the generated PDF.
enum NidPdfLayout {
  /// Places **Front** (top) and **Back** (bottom) centered onto a **single**
  /// PDF page (e.g. A4 portrait) — standard for KYC, banking, and printing.
  topAndBottomSinglePage,

  /// Places **Front** (left) and **Back** (right) side-by-side onto a **single**
  /// PDF page.
  sideBySideSinglePage,

  /// Exports Front and Back as **two separate** PDF pages (`Page 1` and `Page 2`).
  separatePages,
}

/// Physical/visual sizing of NID cards when placed onto a fixed PDF page
/// (`A4`, `Letter`, etc.).
enum NidCardPrintSize {
  /// True 1:1 physical ISO/IEC 7810 ID-1 card dimensions (`85.60 × 53.98 mm` /
  /// `242.65 × 153.01 pt`), ideal for exact-scale physical printing.
  actualIsoId1,

  /// Enlarged, clear ~62% page-width layout (~130 mm wide on A4), ideal for
  /// both digital viewing and readable office printing.
  readableMedium,

  /// Expands cards to fill the maximum available half-page box within margins.
  largeFit,
}

/// Dedicated configuration for National ID / Smart ID / Driver's License
/// scanning (`ScanMode.nidCard`).
class NidScanConfig {
  /// Creates a [NidScanConfig].
  const NidScanConfig({
    this.sides = NidScanSides.frontAndBack,
    this.pdfLayout = NidPdfLayout.topAndBottomSinglePage,
    this.cardPrintSize = NidCardPrintSize.readableMedium,
    this.targetPageSize = PdfPageSize.a4,
    this.gapBetweenCardsPt = 28.0,
    this.pageMarginsPt = 28.0,
    this.normalizeCardAspectRatio = true,
    this.isoCardAspectRatio = 1.5858,
    this.autoAdvanceToBackCapture = true,
    this.allowLayoutSwitchInUi = true,
    this.allowPrintSizeSwitchInUi = true,
    this.showIdFrameGuideInCamera = true,
  });

  /// Whether to capture both Front & Back (`frontAndBack`) or Front only (`frontOnly`).
  final NidScanSides sides;

  /// Default arrangement of Front and Back images in the generated PDF.
  final NidPdfLayout pdfLayout;

  /// Card scaling preset on the target PDF page.
  final NidCardPrintSize cardPrintSize;

  /// Fixed PDF page size used for single-page composite NID layouts (defaults to `PdfPageSize.a4`).
  final PdfPageSize targetPageSize;

  /// Spacing in PDF points (`72 pt = 1 inch`) between Front and Back cards on a single page.
  final double gapBetweenCardsPt;

  /// Outer page margin in PDF points when composing NID cards on a page.
  final double pageMarginsPt;

  /// Normalizes cropped NID card images to standard rectangular ID proportions
  /// ([isoCardAspectRatio]) so angled captures produce clean, uniform cards.
  final bool normalizeCardAspectRatio;

  /// Target `width / height` ratio for horizontal ID cards (`85.60 / 53.98 ≈ 1.5858`).
  final double isoCardAspectRatio;

  /// Automatically opens Back-side capture right after Front-side capture completes.
  final bool autoAdvanceToBackCapture;

  /// Allows the user to switch [NidPdfLayout] interactively on `NidScanScreen`.
  final bool allowLayoutSwitchInUi;

  /// Allows the user to switch [NidCardPrintSize] interactively on `NidScanScreen`.
  final bool allowPrintSizeSwitchInUi;

  /// Draws an ID-card aspect-ratio target frame overlay inside `MultiShotCameraScreen`.
  final bool showIdFrameGuideInCamera;

  /// Expected number of sides (`2` for [NidScanSides.frontAndBack], `1` for [NidScanSides.frontOnly]).
  int get expectedSideCount => sides == NidScanSides.frontAndBack ? 2 : 1;

  /// Creates a modified copy of this [NidScanConfig].
  NidScanConfig copyWith({
    NidScanSides? sides,
    NidPdfLayout? pdfLayout,
    NidCardPrintSize? cardPrintSize,
    PdfPageSize? targetPageSize,
    double? gapBetweenCardsPt,
    double? pageMarginsPt,
    bool? normalizeCardAspectRatio,
    double? isoCardAspectRatio,
    bool? autoAdvanceToBackCapture,
    bool? allowLayoutSwitchInUi,
    bool? allowPrintSizeSwitchInUi,
    bool? showIdFrameGuideInCamera,
  }) => NidScanConfig(
    sides: sides ?? this.sides,
    pdfLayout: pdfLayout ?? this.pdfLayout,
    cardPrintSize: cardPrintSize ?? this.cardPrintSize,
    targetPageSize: targetPageSize ?? this.targetPageSize,
    gapBetweenCardsPt: gapBetweenCardsPt ?? this.gapBetweenCardsPt,
    pageMarginsPt: pageMarginsPt ?? this.pageMarginsPt,
    normalizeCardAspectRatio:
        normalizeCardAspectRatio ?? this.normalizeCardAspectRatio,
    isoCardAspectRatio: isoCardAspectRatio ?? this.isoCardAspectRatio,
    autoAdvanceToBackCapture:
        autoAdvanceToBackCapture ?? this.autoAdvanceToBackCapture,
    allowLayoutSwitchInUi: allowLayoutSwitchInUi ?? this.allowLayoutSwitchInUi,
    allowPrintSizeSwitchInUi:
        allowPrintSizeSwitchInUi ?? this.allowPrintSizeSwitchInUi,
    showIdFrameGuideInCamera:
        showIdFrameGuideInCamera ?? this.showIdFrameGuideInCamera,
  );
}
