import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../../domain/scanner_failure.dart';

/// Raw image file returned by a camera or native scanner capture session.
class CapturedRawPage {
  /// Creates a [CapturedRawPage].
  const CapturedRawPage({required this.path, this.preCropped = false});

  /// Local file path to the captured image.
  final String path;

  /// True when the capture backend already perspective-cropped the document
  /// (e.g. Google ML Kit Document Scanner in `ScannerMode.base`).
  final bool preCropped;
}

/// Interface for launching an external/native single-page or multi-page scanner.
abstract interface class NativePageCaptureService {
  /// Launches the scanner UI and returns `0..N` captured raw pages (empty list
  /// if the user cancelled).
  Future<List<CapturedRawPage>> capturePages({
    required int pageLimit,
    required bool allowGalleryImport,
  });
}

/// Google ML Kit Document Scanner implementation supporting **both** single-page
/// (`pageLimit: 1`) and multi-page (`pageLimit > 1`) native capture on Android.
///
/// Runs strictly in `ScannerMode.base` so ML Kit filters remain disabled and
/// enhancement is handled uniformly by `OpenCvPageProcessor`.
class MlKitPageCaptureService implements NativePageCaptureService {
  /// Creates an [MlKitPageCaptureService].
  const MlKitPageCaptureService();

  /// Returns `true` when running on Android where ML Kit Document Scanner is supported.
  bool get isSupported => Platform.isAndroid;

  @override
  Future<List<CapturedRawPage>> capturePages({
    required int pageLimit,
    required bool allowGalleryImport,
  }) async {
    if (!Platform.isAndroid) {
      throw const CameraUnavailableException(
        'Google ML Kit Document Scanner is only supported on Android. '
        'Use CaptureBackend.auto or CaptureBackend.customCamera on iOS.',
      );
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        pageLimit: pageLimit.clamp(1, 500),
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.base,
        isGalleryImport: allowGalleryImport,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      final captured = <CapturedRawPage>[];
      for (final path in images) {
        if (path.isNotEmpty && await File(path).exists()) {
          captured.add(CapturedRawPage(path: path, preCropped: true));
        }
      }
      return captured;
    } on PlatformException catch (error) {
      final msg = '${error.code} ${error.message}'.toLowerCase();
      if (msg.contains('cancel')) return const [];
      if (msg.contains('permission') || msg.contains('denied')) {
        throw const CameraPermissionDeniedException();
      }
      throw CaptureFailedException(error);
    } finally {
      try {
        await scanner.close();
      } on Object {
        // Scanner activity already closed.
      }
    }
  }
}
