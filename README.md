# custom_pdf_scanner

[![License: MIT](https://img.shields.io/badge/license-MIT-teal.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](https://pub.dev/packages/custom_pdf_scanner)

A highly configurable, **100% local/offline** document scanner SDK for Flutter featuring **Single-Page & Multi-Page batch capture**, **OpenCV perspective cropping & document enhancement filters**, an **embeddable reorderable page list/grid with "+ Add More"**, and a **memory-constant streaming PDF 1.4 generator**.

Built as a modular **SDK for host applications** — no servers, no cloud uploads, no watermarks, and no paid API keys.

---

## Table of Contents

- [Highlights](#highlights)
- [Pipeline Architecture](#pipeline-architecture)
- [Requirements & Platform Setup](#requirements--platform-setup)
- [Quickstart](#quickstart)
  - [1. Multi-Page Scan → Reorderable List → "+ Add More" → PDF](#1-multi-page-scan--reorderable-list---add-more--pdf)
  - [2. Single-Page Scan](#2-single-page-scan)
  - [3. Embed Reorderable Page List Inside Your Own Screen](#3-embed-reorderable-page-list-inside-your-own-screen)
  - [4. Headless Batch Image-to-PDF Pipeline (Zero UI)](#4-headless-batch-image-to-pdf-pipeline-zero-ui)
- [Maximum Customization (`CustomScannerConfig`)](#maximum-customization-customscannerconfig)
  - [Capture Settings (`CaptureConfig`)](#capture-settings-captureconfig)
  - [OpenCV Processing Settings (`ProcessingConfig`)](#opencv-processing-settings-processingconfig)
  - [Reorderable List Settings (`PageListConfig`)](#reorderable-list-settings-pagelistconfig)
  - [PDF Generation Settings (`PdfConfig`)](#pdf-generation-settings-pdfconfig)
  - [Theme, Localization & Custom Builders (`ScannerUiConfig`)](#theme-localization--custom-builders-scanneruiconfig)
- [Troubleshooting & Tips](#troubleshooting--tips)
- [License](#license)

---

## Highlights

- **Single-Page & Multi-Page Modes (`ScanMode`)**
  - **Multi-Page Batch (`ScanMode.multiPage`)**: Capture multiple sheets in one session, process all captured pages sequentially through a background OpenCV isolate with live `BatchProcessingProgress`, review them in a drag-and-drop **reorderable list or grid**, tap **"+ Add More"** to append more single or multi-page batches, and export to a single PDF.
  - **Single-Page (`ScanMode.singlePage`)**: Choose `SinglePageBehavior.immediatePdf` (zero-review instant PDF), `reviewThenPdf` (crop/filter/rotate editor then PDF), or `addToPageList`.
- **Cross-Platform Capture Backends (`CaptureBackend`)**
  - **Android (`CaptureBackend.mlKit`)**: Native Google ML Kit Document Scanner launched in `ScannerMode.base` (disables ML Kit tonal filters so OpenCV handles enhancement consistently; supports both `pageLimit: 1` and `pageLimit: N` + gallery import).
  - **iOS & Android (`CaptureBackend.customCamera`)**: Built-in Flutter Camera (`CameraX` / `AVFoundation`) with live 8-bit luma OpenCV quad boundary overlay, flashlight toggle, steady-edge auto-shutter, and multi-shot thumbnail counter.
- **Production OpenCV Document Pipeline (`dartcv4`)**
  - **Auto & Manual Perspective Crop**: Dual-pass Canny edge + Otsu paper segmentation with surround-contrast verification, outward safety margin (preserving stamps/signatures near paper edges), cubic perspective warp, and interactive 4-corner `CropQuadEditor`.
  - **5 Filters (`ScanFilter`)**:
    - `magicColor`: Illumination flattening, bounded residual shadow lift, Lab-lightness CLAHE & unsharp text sharpening, colored/aged sheet hue preservation, and isolated speckle removal.
    - `natural`: Perspective-cropped sheet at the configured resolution limit with natural lighting.
    - `grayscale`: Clean shadow-flattened 8-bit greyscale document.
    - `blackAndWhite`: Adaptive local **Sauvola** thresholding stored losslessly as 8-bit PNG.
    - `original`: Raw cropped JPEG with zero re-encoding.
  - **Advisory Quality Checks (`PageQualityEvaluator`)**: Non-blocking warnings for blur, camera motion, specular glare, under/over-exposure, and low resolution.
- **Streaming On-Device PDF 1.4 Engine (`LocalPdfBuilder`)**
  - **Zero-re-encode `/DCTDecode` passthrough** for color and grayscale JPEGs (no pixel re-compression or quality loss).
  - **Lossless `/FlateDecode` `/DeviceGray`** streams for `blackAndWhite` PNG pages (razor-sharp text edges without JPEG ringing).
  - **O(1) per-page RAM (~20 MB peak)** via `RandomAccessFile` streaming inside a background isolate — scales cleanly to **100–500 pages**.

---

## Pipeline Architecture

```text
[ Capture (Single or Multi-Page) ]
   ├── ML Kit Base Mode (Android)
   ├── Built-in Live OpenCV Camera (iOS & Android)
   └── External Image Paths (File / Gallery Picker)
                │
                ▼
[ Sequential Background Isolate (OpenCV) ]
   ├── Auto Quad Detection + Cubic Perspective Crop
   ├── Filter: Magic Color | Natural | Grayscale | Sauvola B&W | Original
   └── 240px Thumbnail + Advisory Quality Analysis
                │
                ▼
[ CustomScannerController (Local Reorderable List) ]
   ├── Drag-and-Drop Reorder (List & Grid)
   ├── "+ Add More" (Append Single or Multi-Page Batches)
   └── Per-Page Crop / Rotate / Filter & "Apply Filter to All"
                │
                ▼
[ LocalPdfBuilder (Streaming PDF 1.4 Isolate) ]
   ├── Color/Gray JPEG ──► /DCTDecode XObject (Zero Re-encode)
   ├── Sauvola B&W PNG ──► /FlateDecode /DeviceGray XObject
   └── Page Size (Fit / A4 / Letter / Legal / Custom) ──► Final .pdf
```

---

## Requirements & Platform Setup

### 1. Build-Machine Prerequisites (`dartcv4` Native Build Hook)

`custom_pdf_scanner` uses [`dartcv4`](https://pub.dev/packages/dartcv4), which compiles native C++ OpenCV bindings automatically during `flutter run` / `flutter build` using **CMake** and **Ninja**. Make sure both are on your `PATH`:

- **macOS (Homebrew)**: `brew install cmake ninja`
- **Ubuntu / Debian**: `sudo apt-get install cmake ninja-build`
- **Windows (Winget / Chocolatey)**: `winget install Kitware.CMake Ninja-build.Ninja`

### 2. Add Dependency & OpenCV Module Filter in Your App's `pubspec.yaml`

Add `custom_pdf_scanner` and include the `hooks:` block in your **host application's root `pubspec.yaml`** so `dartcv4` compiles **only** `imgcodecs` and `imgproc` (dramatically reducing first-build compile time and binary size):

```yaml
dependencies:
  flutter:
    sdk: flutter
  custom_pdf_scanner: ^0.1.0

# Recommended: compile only the OpenCV modules used by custom_pdf_scanner
hooks:
  user_defines:
    dartcv4:
      include_modules:
        - imgcodecs
        - imgproc
```

### 3. Android Setup

1. Set **`minSdk = 24`** (or higher) in `android/app/build.gradle` or `android/app/build.gradle.kts`:
   ```kotlin
   defaultConfig {
       minSdk = 24
   }
   ```
2. Add camera permission in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <manifest xmlns:android="http://schemas.android.com/apk/res/android">
       <uses-permission android:name="android.permission.CAMERA" />
       ...
   </manifest>
   ```

### 4. iOS Setup

1. Ensure iOS deployment target is **`13.0` or higher** in `ios/Podfile`:
   ```ruby
   platform :ios, '13.0'
   ```
2. Add `NSCameraUsageDescription` to `ios/Runner/Info.plist`:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Camera access is required to scan documents into PDF.</string>
   ```

---

## Quickstart

### 1. Multi-Page Scan → Reorderable List → "+ Add More" → PDF

```dart
import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/material.dart';

Future<void> scanBatchDocument(BuildContext context) async {
  final ScannedPdfResult? result = await CustomPdfScanner.scanMultiPage(
    context,
    maxPages: 200,
    processing: ProcessingConfig.fromPreset(
      ScanQualityPreset.balanced,
      defaultFilter: ScanFilter.magicColor,
    ),
    pdf: const PdfConfig(
      pageSize: PdfPageSize.a4,
      orientation: PdfPageOrientation.auto,
      marginsPt: EdgeInsets.all(18),
      metadata: PdfDocumentMetadata(
        title: 'Scanned Contract',
        author: 'My App',
      ),
    ),
  );

  if (result != null) {
    debugPrint('PDF File: ${result.pdfFile.path}');
    debugPrint('Pages: ${result.pageCount}, Size: ${result.byteLength} bytes');
    debugPrint('SHA-256: ${result.sha256}');
  }
}
```

### 2. Single-Page Scan

```dart
final ScannedPdfResult? result = await CustomPdfScanner.scanSinglePage(
  context,
  // immediatePdf: auto-crop + enhance + return PDF immediately
  // reviewThenPdf: show preview/filter/crop editor, then return PDF
  // addToPageList: place single capture into the reorderable list
  behavior: SinglePageBehavior.reviewThenPdf,
  processing: const ProcessingConfig(defaultFilter: ScanFilter.blackAndWhite),
);
```

### 3. Embed Reorderable Page List Inside Your Own Screen

Because `custom_pdf_scanner` is designed as an embeddable SDK, you can mount `ScannedPagesReorderableView` directly inside any form, tab, or custom workflow:

```dart
class CustomScanForm extends StatefulWidget {
  const CustomScanForm({super.key});

  @override
  State<CustomScanForm> createState() => _CustomScanFormState();
}

class _CustomScanFormState extends State<CustomScanForm> {
  late final CustomScannerController _controller = CustomScannerController(
    config: CustomScannerConfig.multiPage(),
  );

  @override
  void dispose() {
    _controller.disposeWorkspaceAndController(deleteTempFiles: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(
              child: ScannedPagesReorderableView(
                controller: _controller,
                gridMode: true, // Drag-and-drop grid (or false for ReorderableListView)
                onPageTap: (page) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PageEditorScreen(
                        controller: _controller,
                        pageId: page.id,
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _controller.isBusy
                      ? null
                      : () => _controller.captureAndProcessWithMlKit(
                            modeOverride: ScanMode.multiPage,
                          ),
                  child: const Text('+ Add Multi-Page'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _controller.isEmpty || _controller.isBusy
                      ? null
                      : () async {
                          final res = await _controller.generatePdf();
                          debugPrint('Saved PDF: ${res.pdfPath}');
                        },
                  child: Text('Export PDF (${_controller.pageCount})'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

### 4. Headless Batch Image-to-PDF Pipeline (Zero UI)

Already have photos from `image_picker`, `file_picker`, or your own camera UI? Run the entire OpenCV auto-crop + filter + streaming PDF builder headlessly:

```dart
final ScannedPdfResult result = await CustomPdfScanner.processFilesToPdf(
  imagePaths: ['/path/to/photo1.jpg', '/path/to/photo2.jpg'],
  outputFilePath: '/path/to/output.pdf',
  config: const CustomScannerConfig(
    processing: ProcessingConfig(
      autoCrop: true,
      defaultFilter: ScanFilter.magicColor,
      maxLongEdge: 2400,
      jpegQuality: 86,
    ),
    pdf: PdfConfig(
      pageSize: PdfPageSize.fitToImage,
      deleteTempFilesAfterExport: true,
    ),
  ),
  onProcessingProgress: (p) => debugPrint('OpenCV: ${p.completed}/${p.total}'),
  onPdfProgress: (p) => debugPrint('PDF: ${p.completedPages}/${p.totalPages}'),
);
```

---

## Maximum Customization (`CustomScannerConfig`)

### Capture Settings (`CaptureConfig`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scanMode` | `ScanMode` | `multiPage` | `ScanMode.singlePage` or `ScanMode.multiPage`. |
| `singlePageBehavior` | `SinglePageBehavior` | `reviewThenPdf` | `immediatePdf`, `reviewThenPdf`, or `addToPageList`. |
| `backend` | `CaptureBackend` | `auto` | `auto` (ML Kit on Android, OpenCV Camera on iOS), `mlKit`, or `customCamera`. |
| `maxPages` | `int?` | `200` | Maximum total pages (`null` for unlimited). |
| `allowGalleryImport` | `bool` | `true` | Enables gallery photo import in ML Kit scanner. |
| `enableTorch` | `bool` | `true` | Shows torch toggle in `customCamera`. |
| `autoCaptureOnStableEdge` | `bool` | `true` | Auto-fires shutter when OpenCV quad holds steady. |
| `autoCaptureStableFrames` | `int` | `4` | Consecutive steady preview frames before auto-capture. |
| `cameraResolution` | `ScannerCameraResolution` | `max` | `medium`, `high`, `veryHigh`, `ultraHigh`, or `max`. |

### OpenCV Processing Settings (`ProcessingConfig`)

Use `ProcessingConfig.fromPreset(ScanQualityPreset.compact | balanced | high)` or tune any individual OpenCV parameter:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `defaultFilter` | `ScanFilter` | `magicColor` | Default filter (`magicColor`, `natural`, `grayscale`, `blackAndWhite`, `original`). |
| `availableFilters` | `List<ScanFilter>` | All 5 | Restrict or reorder filters shown in UI. |
| `autoCrop` | `bool` | `true` | Runs OpenCV Canny+Otsu corner detection & perspective warp. |
| `cropSafetyMargin` | `double` | `0.008` | Outward margin fraction around detected corners (~2 mm on A4). |
| `minCropConfidence` | `double` | `0.55` | Minimum confidence (`0..1`) to accept an automatic crop. |
| `maxLongEdge` | `int` | `2400` | Max pixel long edge (`0` keeps full native camera resolution). |
| `jpegQuality` | `int` | `86` | Output JPEG quality (`1..100`) for color/grayscale filters. |
| `pngCompression` | `int` | `3` | Lossless PNG compression (`0..9`) for `blackAndWhite`. |
| `claheClipLimit` | `double` | `1.4` | Lab lightness local contrast boost limit. |
| `sharpenAmount` | `double` | `0.5` | Resolution-aware unsharp mask strength (`0` = off). |
| `paperWhitePoint` | `double` | `0.98` | Target paper whitening ceiling. |
| `residualShadowRemoval` | `bool` | `true` | Bounded additive shadow lift outside foreground ink. |
| `speckleRemoval` | `bool` | `true` | Removes isolated dust specks while protecting punctuation. |
| `blackWhiteSauvolaK` | `double` | `0.12` | Sauvola adaptive threshold sensitivity `k`. |
| `enableQualityChecks` | `bool` | `true` | Runs blur, motion, glare, and exposure checks. |
| `useIsolate` | `bool` | `true` | Runs OpenCV pipelines inside `Isolate.run`. |

### Reorderable List Settings (`PageListConfig`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enableReorder` | `bool` | `true` | Enables drag-and-drop reordering in list and grid views. |
| `layout` | `PageListLayout` | `toggleable` | `list`, `grid`, or `toggleable` (toolbar button). |
| `gridCrossAxisCount` | `int` | `2` | Columns in grid view. |
| `allowAddMore` | `bool` | `true` | Enables "+ Add More" button to append new scans into the list. |
| `allowAddSingleOrMultiChoice` | `bool` | `true` | Lets user choose "+ Scan Multiple Pages" or "+ Scan Single Page". |
| `allowBatchFilterApply` | `bool` | `true` | Enables "Apply Filter to All Pages" batch action. |
| `allowEditCrop` / `allowRotate` / `allowRetake` / `allowDelete` | `bool` | `true` | Toggle individual per-page editing actions. |

### PDF Generation Settings (`PdfConfig`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `customOutputFilePath` | `String?` | `null` | Exact `.pdf` path to write (overrides directory + prefix). |
| `outputDirectoryPath` | `String?` | `null` | Output folder (defaults to temporary directory). |
| `fileNamePrefix` | `String` | `'scan_'` | Filename prefix when auto-naming PDFs. |
| `pageSize` | `PdfPageSize` | `fitToImage` | `fitToImage`, `a4`, `letter`, `legal`, or `PdfPageSize.custom(...)`. |
| `orientation` | `PdfPageOrientation` | `auto` | `auto` (matches image aspect), `portrait`, or `landscape`. |
| `marginsPt` | `EdgeInsets` | `EdgeInsets.zero` | Page margins in PDF points (`72 pt = 1 inch`). |
| `imageFit` | `PdfImageFit` | `contain` | `contain`, `cover`, or `fill`. |
| `dpi` | `double` | `150.0` | DPI scaling used by `PdfPageSize.fitToImage`. |
| `metadata` | `PdfDocumentMetadata` | `const PdfDocumentMetadata()` | Unicode `/Title`, `/Author`, `/Subject`, `/Keywords`, `/Creator`. |
| `computeSha256` | `bool` | `true` | Computes SHA-256 hex digest of the generated `.pdf`. |
| `deleteTempFilesAfterExport` | `bool` | `false` | Deletes intermediate page images immediately after PDF export. |

### Theme, Localization & Custom Builders (`ScannerUiConfig`)

```dart
final uiConfig = ScannerUiConfig(
  theme: ScannerThemeData.dark(primaryColor: Colors.indigoAccent),
  strings: const ScannerStrings(
    pagesScreenTitle: 'স্ক্যান করা পৃষ্ঠা',
    addMoreButton: 'আরও যোগ করুন',
    generatePdfButton: 'পিডিএফ তৈরি করুন',
  ),
  // Optional: completely replace page cards or bottom action bar with your own widgets!
  pageTileBuilder: (context, page, index, onTap, onDelete) { ... },
  bottomBarBuilder: (context, count, busy, onAddMore, onGeneratePdf) { ... },
);
```

---

## Troubleshooting & Tips

- **First build takes 2–5 minutes**: On the very first build for a target ABI, `dartcv4` compiles native OpenCV C++ sources via CMake + Ninja. Subsequent builds reuse `.dart_tool/hooks_runner/` cache and finish in seconds. Make sure the `hooks:` block from [Step 2](#2-add-dependency--opencv-module-filter-in-your-apps-pubspecyaml) is in your app's `pubspec.yaml`.
- **iOS Simulator**: Camera hardware and Google ML Kit Document Scanner require a physical device for live camera capture; headless processing (`CustomPdfScanner.processFilesToPdf` and `controller.addImageFiles`) works on both simulators and physical devices.
- **Keeping intermediate page images**: Leave `PdfConfig.deleteTempFilesAfterExport: false` (default) if you want to access individual processed page files via `result.pages[i].exportPath` after generating the PDF, or set it to `true` to clean up temporary disk files automatically.

---

## License

Released under the **MIT License**. See [LICENSE](LICENSE) for full text.
