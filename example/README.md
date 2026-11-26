# custom_pdf_scanner Example

Interactive demo application for [`custom_pdf_scanner`](../README.md) showcasing:

1. **Modal Launcher Tab (`CustomPdfScanner.scan`)**:
   - Switch dynamically between `ScanMode.multiPage` and `ScanMode.singlePage` (`reviewThenPdf`, `immediatePdf`, `addToPageList`).
   - Switch between `CaptureBackend.auto`, `customCamera` (live OpenCV edge overlay), and `mlKit`.
   - Test `ScanFilter` (`Magic Color`, `Natural`, `Grayscale`, `Black & White`, `Original`), `ScanQualityPreset`, and `PdfPageSize` (`Fit to Page`, `A4`, `US Letter`).
2. **Embedded Reorderable List Tab (`ScannedPagesReorderableView`)**:
   - Demonstrates embedding `CustomScannerController` + `ScannedPagesReorderableView` directly inside your own app screen with custom `+1 Page`, `+Multi`, and `Save PDF` buttons.

## Running Locally on a Device

If `android/` or `ios/` platform folders are not present (for example, when downloaded from `pub.dev`), generate them once:

```bash
cd example
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Ensure `minSdk = 24` in `android/app/build.gradle.kts`, `<uses-permission android:name="android.permission.CAMERA" />` in `AndroidManifest.xml`, and `NSCameraUsageDescription` in `ios/Runner/Info.plist`.
