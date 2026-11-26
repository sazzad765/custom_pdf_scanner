# custom_pdf_scanner

[![License: MIT](https://img.shields.io/badge/license-MIT-teal.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](https://pub.dev/packages/custom_pdf_scanner)

A highly configurable, **100% local/offline** document & NID card scanner SDK for Flutter featuring **Single-Page, Multi-Page Batch, and Guided NID Card (`ScanMode.nidCard`) capture**, **OpenCV perspective cropping & document enhancement filters**, an **embeddable reorderable page list/grid with "+ Add More"**, and a **memory-constant streaming PDF 1.4 generator**.

Built as a modular **SDK for host applications** — no servers, no cloud uploads, no watermarks, and no paid API keys.

---

## Table of Contents

- [Highlights](#highlights)
- [Requirements & Platform Setup](#requirements--platform-setup)
- [Quickstart](#quickstart)
  - [1. Multi-Page Scan → Reorderable List → "+ Add More" → PDF](#1-multi-page-scan--reorderable-list---add-more--pdf)
  - [2. NID / ID Card Scan (`ScanMode.nidCard` — Front & Back on 1 Page)](#2-nid--id-card-scan-scanmodenidcard--front--back-on-1-page)
  - [3. Single-Page Scan](#3-single-page-scan)
  - [4. Embed Reorderable Page List Inside Your Own Screen](#4-embed-reorderable-page-list-inside-your-own-screen)
  - [5. Headless Batch Image-to-PDF Pipeline (Zero UI)](#5-headless-batch-image-to-pdf-pipeline-zero-ui)
- [Maximum Customization (`CustomScannerConfig`)](#maximum-customization-customscannerconfig)
  - [Capture Settings (`CaptureConfig`)](#capture-settings-captureconfig)
  - [NID Card Settings (`NidScanConfig`)](#nid-card-settings-nidscanconfig)
  - [OpenCV Processing Settings (`ProcessingConfig`)](#opencv-processing-settings-processingconfig)
  - [Reorderable List Settings (`PageListConfig`)](#reorderable-list-settings-pagelistconfig)
  - [PDF Generation Settings (`PdfConfig`)](#pdf-generation-settings-pdfconfig)
  - [Theme, Localization & Custom Builders (`ScannerUiConfig`)](#theme-localization--custom-builders-scanneruiconfig)
- [License](#license)

---

## Highlights

- **3 Scan Modes (`ScanMode`)**
  - **Multi-Page Batch (`ScanMode.multiPage`)**: Capture multiple sheets in one session, process all captured pages sequentially through a background OpenCV isolate with live `BatchProcessingProgress`, review them in a drag-and-drop **reorderable list or grid**, tap **"+ Add More"** to append more single or multi-page batches, and export to a single PDF.
  - **NID / Smart ID Card (`ScanMode.nidCard`)**: Guided **Front Side & Back Side** (or Front-only) card workflow (`NidScanScreen`) with an ISO ID-1 camera framing overlay, one-tap Front ⇅ Back swap, and **composite single-page A4/Letter PDF generation** (Front on top + Back below, side-by-side on 1 page, or 2 separate pages) with `readableMedium`, true `1:1` physical ISO ID-1 (`85.6 × 53.98 mm`), or `largeFit` sizing!
  - **Single-Page (`ScanMode.singlePage`)**: Choose `SinglePageBehavior.immediatePdf` (zero-review instant PDF), `reviewThenPdf` (crop/filter/rotate editor then PDF), or `addToPageList`.
- **Cross-Platform Capture Backends (`CaptureBackend`)**
  - **Android (`CaptureBackend.mlKit`)**: Native Google ML Kit Document Scanner launched in `ScannerMode.base` (disables ML Kit tonal filters so OpenCV handles enhancement consistently).
  - **iOS & Android (`CaptureBackend.customCamera`)**: Built-in Flutter Camera (`CameraX` / `AVFoundation`) with live 8-bit luma OpenCV quad boundary overlay, ID-card framing guide, flashlight toggle, steady-edge auto-shutter, and multi-shot thumbnail counter.
- **Production OpenCV Document Pipeline (`dartcv4`)**
  - **Auto & Manual Perspective Crop**: Dual-pass Canny edge + Otsu paper segmentation with surround-contrast verification, outward safety margin, cubic perspective warp, and interactive 4-corner `CropQuadEditor`.
  - **5 Filters (`ScanFilter`)**: `magicColor`, `natural`, `grayscale`, `blackAndWhite` (lossless Sauvola adaptive threshold), and `original`.
  - **Advisory Quality Checks (`PageQualityEvaluator`)**: Non-blocking warnings for blur, camera motion, specular glare, under/over-exposure, and low resolution.
- **Streaming On-Device PDF 1.4 Engine (`LocalPdfBuilder`)**
  - **Zero-re-encode `/DCTDecode` passthrough** for color and grayscale JPEGs.
  - **Lossless `/FlateDecode` `/DeviceGray`** streams for `blackAndWhite` PNG pages.
  - **O(1) per-page RAM (~20 MB peak)** — scales cleanly from 1-page composite NID sheets up to **500-page** document batches.

---

## Requirements & Platform Setup

### 1. Build-Machine Prerequisites (`dartcv4` Native Build Hook)

`custom_pdf_scanner` uses [`dartcv4`](https://pub.dev/packages/dartcv4), which compiles native C++ OpenCV bindings automatically during `flutter run` / `flutter build` using **CMake** and **Ninja**:

- **macOS (Homebrew)**: `brew install cmake ninja`
- **Ubuntu / Debian**: `sudo apt-get install cmake ninja-build`
- **Windows (Winget)**: `winget install Kitware.CMake Ninja-build.Ninja`

### 2. Add Dependency & OpenCV Module Filter in Your App's `pubspec.yaml`

Add `custom_pdf_scanner` and include the `hooks:` block in your **host application's root `pubspec.yaml`** so `dartcv4` compiles **only** `imgcodecs` and `imgproc`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  custom_pdf_scanner: ^0.2.0

# Recommended: compile only the OpenCV modules used by custom_pdf_scanner
hooks:
  user_defines:
    dartcv4:
      include_modules:
        - imgcodecs
        - imgproc
```

### 3. Android & iOS Permissions

- **Android**: Set `minSdk = 24` in `android/app/build.gradle(.kts)` and add `<uses-permission android:name="android.permission.CAMERA" />` in `AndroidManifest.xml`.
- **iOS**: Set `platform :ios, '13.0'` in `ios/Podfile` and add `NSCameraUsageDescription` in `ios/Runner/Info.plist`.

---

## Quickstart

### 1. Multi-Page Scan → Reorderable List → "+ Add More" → PDF

```dart
import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';

final ScannedPdfResult? result = await CustomPdfScanner.scanMultiPage(
  context,
  maxPages: 200,
  processing: ProcessingConfig.fromPreset(
    ScanQualityPreset.balanced,
    defaultFilter: ScanFilter.magicColor,
  ),
  pdf: const PdfConfig(
    pageSize: PdfPageSize.a4,
    marginsPt: EdgeInsets.all(18),
  ),
);
```

### 2. NID / ID Card Scan (`ScanMode.nidCard` — Front & Back on 1 Page)

```dart
final ScannedPdfResult? nidResult = await CustomPdfScanner.scanNidCard(
  context,
  nid: const NidScanConfig(
    sides: NidScanSides.frontAndBack,
    pdfLayout: NidPdfLayout.topAndBottomSinglePage, // Both sides on 1 A4 page!
    cardPrintSize: NidCardPrintSize.readableMedium, // or NidCardPrintSize.actualIsoId1
    targetPageSize: PdfPageSize.a4,
  ),
);

if (nidResult != null) {
  debugPrint('Saved ${nidResult.pageCount}-page NID PDF: ${nidResult.pdfPath}');
}
```

### 3. Single-Page Scan

```dart
final ScannedPdfResult? result = await CustomPdfScanner.scanSinglePage(
  context,
  behavior: SinglePageBehavior.reviewThenPdf, // or SinglePageBehavior.immediatePdf
);
```

### 4. Embed Reorderable Page List Inside Your Own Screen

```dart
final controller = CustomScannerController(
  config: CustomScannerConfig.multiPage(),
);

// Inside your Widget build():
ScannedPagesReorderableView(
  controller: controller,
  gridMode: true,
);
```

### 5. Headless Batch Image-to-PDF Pipeline (Zero UI)

```dart
final ScannedPdfResult result = await CustomPdfScanner.processFilesToPdf(
  imagePaths: ['/path/to/nid_front.jpg', '/path/to/nid_back.jpg'],
  outputFilePath: '/path/to/nid_sheet.pdf',
  config: CustomScannerConfig.nidCard(),
);
```

---

## Maximum Customization (`CustomScannerConfig`)

### Capture Settings (`CaptureConfig`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scanMode` | `ScanMode` | `multiPage` | `singlePage`, `multiPage`, or `nidCard`. |
| `singlePageBehavior` | `SinglePageBehavior` | `reviewThenPdf` | `immediatePdf`, `reviewThenPdf`, or `addToPageList`. |
| `backend` | `CaptureBackend` | `auto` | `auto`, `mlKit` (Android), or `customCamera` (Android & iOS). |
| `maxPages` | `int?` | `200` | Maximum total pages (`null` for unlimited). |
| `allowGalleryImport` | `bool` | `true` | Enables gallery photo import in ML Kit scanner. |
| `enableTorch` | `bool` | `true` | Shows torch toggle in `customCamera`. |
| `autoCaptureOnStableEdge` | `bool` | `true` | Auto-fires shutter when OpenCV quad holds steady. |

### NID Card Settings (`NidScanConfig`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `sides` | `NidScanSides` | `frontAndBack` | `frontAndBack` (2 sides) or `frontOnly` (1 side). |
| `pdfLayout` | `NidPdfLayout` | `topAndBottomSinglePage` | `topAndBottomSinglePage`, `sideBySideSinglePage`, or `separatePages`. |
| `cardPrintSize` | `NidCardPrintSize` | `readableMedium` | `readableMedium` (~62% width), `actualIsoId1` (`85.6 × 53.98 mm` 1:1 scale), or `largeFit`. |
| `targetPageSize` | `PdfPageSize` | `PdfPageSize.a4` | Sheet size for composite single-page NID layouts (`a4`, `letter`, etc.). |
| `gapBetweenCardsPt` | `double` | `28.0` | Spacing in PDF points between Front and Back cards on 1 page. |
| `normalizeCardAspectRatio` | `bool` | `true` | Normalizes card dimensions on the PDF sheet to `isoCardAspectRatio` (`1.5858`). |
| `autoAdvanceToBackCapture` | `bool` | `true` | Automatically launches Back capture after Front capture finishes. |
| `allowLayoutSwitchInUi` | `bool` | `true` | Shows interactive layout chips on `NidScanScreen`. |
| `allowPrintSizeSwitchInUi` | `bool` | `true` | Shows interactive print-size chips on `NidScanScreen`. |
| `showIdFrameGuideInCamera` | `bool` | `true` | Draws rounded ID-1 card target frame inside `MultiShotCameraScreen`. |

### OpenCV Processing Settings (`ProcessingConfig`)

Use `ProcessingConfig.fromPreset(ScanQualityPreset.compact | balanced | high)` or customize `defaultFilter`, `availableFilters`, `autoCrop`, `cropSafetyMargin`, `minCropConfidence`, `maxLongEdge`, `jpegQuality`, `pngCompression`, `claheClipLimit`, `sharpenAmount`, `paperWhitePoint`, `residualShadowRemoval`, `speckleRemoval`, `blackWhiteSauvolaK`, and `enableQualityChecks`.

### Reorderable List Settings (`PageListConfig`)

Customize `enableReorder`, `layout` (`list`, `grid`, `toggleable`), `gridCrossAxisCount`, `allowAddMore`, `allowAddSingleOrMultiChoice`, `allowBatchFilterApply`, `allowEditCrop`, `allowRotate`, `allowRetake`, and `allowDelete`.

### PDF Generation Settings (`PdfConfig`)

Customize `customOutputFilePath`, `outputDirectoryPath`, `fileNamePrefix`, `pageSize` (`fitToImage`, `a4`, `letter`, `legal`, `custom`), `orientation`, `marginsPt`, `imageFit`, `dpi`, `metadata`, `computeSha256`, and `deleteTempFilesAfterExport`.

### Theme, Localization & Custom Builders (`ScannerUiConfig`)

Customize `ScannerThemeData` (`.light()` / `.dark()`), `ScannerStrings` (including `nidScreenTitle`, `nidFrontLabel`, `nidBackLabel`, etc.), `ScannerIcons`, `pageTileBuilder`, `emptyStateBuilder`, and `bottomBarBuilder`.

---

## License

Released under the **MIT License**. See [LICENSE](LICENSE) for full text.
