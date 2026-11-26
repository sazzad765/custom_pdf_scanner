/// Configurable, 100% local/offline document scanner SDK for Flutter with
/// single-page & multi-page batch capture, OpenCV perspective cropping &
/// enhancement filters, an embeddable reorderable page list/grid with
/// "+ Add More", and a streaming on-device PDF 1.4 generator.
///
/// ## Quickstart
///
/// ```dart
/// import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
///
/// final result = await CustomPdfScanner.scanMultiPage(context);
/// if (result != null) {
///   print('Saved ${result.pageCount} pages to ${result.pdfPath}');
/// }
/// ```
///
/// For embedded UI workflows, instantiate [CustomScannerController] and mount
/// [ScannedPagesReorderableView] inside your own widget tree. For headless file
/// processing without UI, call [CustomPdfScanner.processFilesToPdf] or
/// [LocalPdfBuilder].
library;

// Configuration & Theme
export 'src/config/capture_config.dart';
export 'src/config/custom_scanner_config.dart';
export 'src/config/page_list_config.dart';
export 'src/config/pdf_config.dart';
export 'src/config/processing_config.dart';
export 'src/config/scanner_ui_config.dart';

// Controllers
export 'src/controller/custom_camera_controller.dart';
export 'src/controller/custom_scanner_controller.dart';

// Domain Models
export 'src/domain/crop_corners.dart';
export 'src/domain/crop_models.dart';
export 'src/domain/page_quality.dart';
export 'src/domain/scan_filter.dart';
export 'src/domain/scanned_page.dart';
export 'src/domain/scanned_pdf_result.dart';
export 'src/domain/scanner_failure.dart';

// Headless Services & Extensibility Interfaces
export 'src/infrastructure/camera/camera_stream_service.dart';
export 'src/infrastructure/camera/flutter_camera_stream_service.dart';
export 'src/infrastructure/camera/page_capture_service.dart';
export 'src/infrastructure/crop/document_detector.dart';
export 'src/infrastructure/crop/jpeg_header.dart';
export 'src/infrastructure/crop/opencv_document_detector.dart';
export 'src/infrastructure/crop/opencv_perspective_cropper.dart';
export 'src/infrastructure/crop/perspective_cropper.dart';
export 'src/infrastructure/pdf/local_pdf_builder.dart';
export 'src/infrastructure/processing/opencv_page_processor.dart';
export 'src/infrastructure/processing/page_quality_evaluator.dart';

// Turnkey Launcher, Screens & Embeddable Widgets
export 'src/presentation/custom_pdf_scanner_launcher.dart';
export 'src/presentation/screens/multi_shot_camera_screen.dart';
export 'src/presentation/screens/page_crop_screen.dart';
export 'src/presentation/screens/page_editor_screen.dart';
export 'src/presentation/screens/scanned_pages_screen.dart';
export 'src/presentation/widgets/camera_boundary_overlay.dart';
export 'src/presentation/widgets/crop_quad_editor.dart';
export 'src/presentation/widgets/scanned_pages_reorderable_view.dart';
