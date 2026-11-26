## 0.2.0

* **Added NID / ID Card Scan Mode (`ScanMode.nidCard`)**:
  * Added `CustomPdfScanner.scanNidCard(...)`, `CustomScannerConfig.nidCard(...)`, and `NidScanConfig`.
  * Added dedicated `NidScanScreen` with guided **Front Side** & **Back Side** card slots, one-tap Front ⇅ Back swap (`swapFrontAndBack()`), inline crop/rotate/retake controls, and interactive layout/size chips.
  * Added **single-page composite PDF generation** (`NidPdfLayout.topAndBottomSinglePage` and `sideBySideSinglePage`) placing both Front and Back NID XObjects onto a single A4/Letter PDF sheet without re-encoding, plus `NidCardPrintSize` presets (`readableMedium`, `actualIsoId1` `85.6 × 53.98 mm`, and `largeFit`).
  * Added ID-1 card framing guide overlay inside `MultiShotCameraScreen`.
* **Enhanced `example/` app**:
  * Added interactive `PDFView` PDF preview screen, Save-to-Device export, persistent local Scan History tab, and NID Card mode playground controls.

## 0.1.0

* **Initial release** of `custom_pdf_scanner`.
* **Single-Page & Multi-Page Capture (`ScanMode`)**:
  * Multi-page batch capture with sequential background-isolate OpenCV processing and live `BatchProcessingProgress` reporting.
  * Single-page capture modes (`SinglePageBehavior.immediatePdf`, `reviewThenPdf`, and `addToPageList`).
  * Pluggable capture backends (`CaptureBackend.auto`, `mlKit` on Android in `ScannerMode.base`, and `customCamera` with live OpenCV boundary overlay, torch, and steady-edge auto-capture on Android & iOS).
* **OpenCV Perspective Crop & Document Filters (`dartcv4`)**:
  * Automatic 4-corner Canny + Otsu document detection with safety margin and interactive manual 4-corner `CropQuadEditor`.
  * Five filters: `magicColor`, `natural`, `grayscale`, `blackAndWhite` (lossless Sauvola adaptive threshold), and `original`.
  * Advisory pre- and post-processing quality diagnostics (`PageQualityEvaluator`) for blur, motion, glare, exposure, and resolution.
* **Embeddable Reorderable Page List & Controller**:
  * `CustomScannerController` and `ScannedPagesReorderableView` supporting drag-and-drop list/grid reordering, "+ Add More" batch/single appending, per-page crop/rotate/filter editing, and batch filter application (`applyFilterToAll`).
* **Streaming Local PDF 1.4 Engine (`LocalPdfBuilder`)**:
  * Zero-re-encode `/DCTDecode` JPEG passthrough for color and grayscale pages.
  * Lossless `/FlateDecode` `/DeviceGray` streams for crisp Black & White PNG pages.
  * Configurable `PdfPageSize` (`fitToImage`, `a4`, `letter`, `legal`, `custom`), `PdfPageOrientation`, `marginsPt`, `imageFit`, `dpi`, SHA-256 checksums, and Unicode UTF-16BE PDF metadata.
* **SDK Customization**:
  * Full configuration via `CustomScannerConfig`, `ScannerThemeData` (light/dark + custom tokens), `ScannerStrings` (i18n), `ScannerIcons`, and custom widget builders.
