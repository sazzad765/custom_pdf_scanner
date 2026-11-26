## 0.1.0

* Initial release of `custom_pdf_scanner`.
* Added single-page and multi-page document capture (`ScanMode.singlePage` and `ScanMode.multiPage`) with ML Kit (Android) and custom Flutter camera + live OpenCV boundary detection (Android & iOS).
* Added background-isolate OpenCV perspective cropping, illumination flattening, shadow removal, speckle cleanup, and 4 enhancement filters (`Natural`, `Magic Color`, `Grayscale`, `Black & White` Sauvola) plus raw cropped original mode.
* Added `CustomScannerController` and embeddable `ScannedPagesReorderableView` supporting drag-and-drop reordering, "+ Add More" batch/single scanning, per-page crop/rotate/filter editing, and batch filter application.
* Added `LocalPdfBuilder` for memory-constant on-device streaming PDF generation (`/DCTDecode` zero-re-encode JPEG passthrough and `/FlateDecode` lossless 8-bit grayscale/B&W streams) with configurable page sizes (`fitToImage`, `A4`, `Letter`, `Legal`, custom), margins, orientation, and metadata.
* Added comprehensive `CustomScannerConfig`, `ScannerThemeData`, `ScannerStrings`, and custom UI builder hooks.
