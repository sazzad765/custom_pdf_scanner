# custom_pdf_scanner

A configurable, **100% local/offline** document scanner SDK for Flutter with **Single-Page & Multi-Page capture**, **OpenCV perspective cropping & enhancement filters**, an **embeddable reorderable page list with "+ Add More"**, and a **memory-constant streaming PDF generator**.

Zero servers, zero network calls, zero subscriptions — everything runs locally on the device.

---

## Features

- **Single-Page & Multi-Page Capture (`ScanMode`)**
  - **Multi-Page Batch Mode**: Scan multiple pages at once, batch-enhance every page sequentially in a background OpenCV isolate with live progress, land in a **reorderable page list/grid**, and tap **"+ Add More"** to append additional single or multi-page scans.
  - **Single-Page Mode**: Choose `immediatePdf` (1-tap auto-crop + filter + PDF), `reviewThenPdf` (preview/filter/crop then PDF), or `addToPageList`.
  - **Cross-Platform Capture Backends**: Uses Google ML Kit Document Scanner (`ScannerMode.base`, Android) and a built-in Flutter Camera with **live OpenCV boundary overlay & auto-shutter** (iOS & Android).
- **Production OpenCV Image Pipeline (`dartcv4`)**
  - Automatic 4-corner Canny + Otsu quad detection with safety margin and interactive manual 4-corner perspective crop editor.
  - 5 document filters: **Magic Color** (illumination flattening, shadow lift, Lab ink sharpening, colored-paper/stamp preservation, speckle removal), **Natural**, **Grayscale**, **Black & White** (adaptive Sauvola threshold saved losslessly), and **Original**.
  - Advisory quality diagnostics (blur, camera motion, glare, exposure, resolution).
- **Streaming On-Device PDF 1.4 Engine (`LocalPdfBuilder`)**
  - **Zero-re-encode `/DCTDecode` JPEG passthrough** for color and grayscale pages.
  - **Lossless `/FlateDecode` `/DeviceGray`** streams for crisp Black & White pages without JPEG mosquito ringing.
  - Constant ~20 MB RAM footprint even for **100–500 page** documents.
  - Configurable `PdfPageSize` (`fitToImage`, `a4`, `letter`, `legal`, `custom`), `PdfPageOrientation` (`auto`, `portrait`, `landscape`), `marginsPt`, `imageFit`, `dpi`, and Unicode PDF metadata.
- **Designed as an SDK for Host Apps**
  - Use the 1-line modal launcher (`CustomPdfScanner.scan`), embed `ScannedPagesReorderableView` + `CustomScannerController` inside your own UI, or call the headless pipeline (`CustomPdfScanner.processFilesToPdf`).

---

## Installation & Platform Setup

### 1. Add dependency

```yaml
dependencies:
  custom_pdf_scanner: ^0.1.0
```

### 2. Configure OpenCV build modules in your app's `pubspec.yaml` (Recommended)

`custom_pdf_scanner` uses [`dartcv4`](https://pub.dev/packages/dartcv4) (requires CMake & Ninja on your build machine when compiling native OpenCV bindings). Add this block to your **root app's `pubspec.yaml`** so only `imgcodecs` and `imgproc` are compiled, keeping builds fast and app size small:

```yaml
hooks:
  user_defines:
    dartcv4:
      include_modules:
        - imgcodecs
        - imgproc
```

### 3. Android & iOS Permissions

- **Android** (`android/app/build.gradle` -> `minSdk = 24`, and `AndroidManifest.xml`):
  ```xml
  <uses-permission android:name="android.permission.CAMERA" />
  ```
- **iOS** (`ios/Runner/Info.plist`):
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Camera access is required to scan documents into PDF.</string>
  ```

---

## Usage

### 1. Multi-Page Scan -> Reorderable List -> "+ Add More" -> Local PDF

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
    marginsPt: EdgeInsets.all(16),
    metadata: PdfDocumentMetadata(title: 'Invoice Batch'),
  ),
);

if (result != null) {
  print('PDF saved at: ${result.pdfPath} (${result.pageCount} pages)');
}
```

### 2. Single-Page Scan

```dart
final ScannedPdfResult? result = await CustomPdfScanner.scanSinglePage(
  context,
  behavior: SinglePageBehavior.reviewThenPdf, // or SinglePageBehavior.immediatePdf
);
```

### 3. Embed the Reorderable List Inside Your Own Screen

```dart
final controller = CustomScannerController(
  config: CustomScannerConfig.multiPage(),
);

// Inside your Widget build():
Column(
  children: [
    Expanded(
      child: ScannedPagesReorderableView(
        controller: controller,
        gridMode: false, // true for drag-and-drop grid, false for ReorderableListView
      ),
    ),
    Row(
      children: [
        OutlinedButton(
          onPressed: () => controller.addImageFiles(['/path/to/photo1.jpg']),
          child: const Text('Add More'),
        ),
        FilledButton(
          onPressed: () async {
            final pdf = await controller.generatePdf();
            debugPrint('Created: ${pdf.pdfPath}');
          },
          child: const Text('Export PDF'),
        ),
      ],
    ),
  ],
);
```

### 4. Maximum Customization (`CustomScannerConfig`)

Every stage is configurable via `CustomScannerConfig`:

| Config Group | Key Options |
|---|---|
| `CaptureConfig` | `scanMode` (`singlePage` / `multiPage`), `singlePageBehavior`, `backend` (`auto` / `mlKit` / `customCamera`), `maxPages`, `allowGalleryImport`, `enableTorch`, `autoCaptureOnStableEdge`, `cameraResolution` |
| `ProcessingConfig` | `defaultFilter`, `availableFilters`, `autoCrop`, `cropSafetyMargin`, `minCropConfidence`, `maxLongEdge`, `jpegQuality`, `pngCompression`, `claheClipLimit`, `sharpenAmount`, `paperWhitePoint`, `blackWhiteSauvolaK`, `speckleRemoval`, `residualShadowRemoval`, `enableQualityChecks` |
| `PageListConfig` | `enableReorder`, `layout` (`list` / `grid` / `toggleable`), `allowAddMore`, `allowAddSingleOrMultiChoice`, `allowEditCrop`, `allowChangeFilter`, `allowBatchFilterApply`, `allowRotate`, `allowRetake`, `allowDelete` |
| `PdfConfig` | `outputDirectoryPath`, `customOutputFilePath`, `fileNamePrefix`, `pageSize` (`fitToImage`, `a4`, `letter`, `legal`, `custom`), `orientation`, `marginsPt`, `imageFit`, `dpi`, `metadata`, `deleteTempFilesAfterExport` |
| `ScannerUiConfig` | `theme` (`ScannerThemeData.light()` / `.dark()`), `strings` (`ScannerStrings` for localization), `icons` (`ScannerIcons`), `pageTileBuilder`, `emptyStateBuilder`, `bottomBarBuilder` |

### 5. Pure Headless Batch Pipeline (Zero UI)

```dart
final result = await CustomPdfScanner.processFilesToPdf(
  imagePaths: ['/path/page1.jpg', '/path/page2.jpg'],
  outputFilePath: '/path/output.pdf',
  config: const CustomScannerConfig(
    processing: ProcessingConfig(defaultFilter: ScanFilter.blackAndWhite),
  ),
);
```

---

## License

MIT License — see [LICENSE](LICENSE).
