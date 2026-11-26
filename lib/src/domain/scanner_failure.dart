/// Recoverable exception thrown by capture, OpenCV processing, storage, or
/// local PDF generation in `custom_pdf_scanner`.
sealed class ScannerFailure implements Exception {
  /// Creates a [ScannerFailure] with a human-readable [message] and optional [cause].
  const ScannerFailure(this.message, {this.cause});

  /// Description of what went wrong.
  final String message;

  /// Underlying platform or I/O error, if available.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// Camera hardware or native document scanner is unavailable on this device.
class CameraUnavailableException extends ScannerFailure {
  /// Creates a [CameraUnavailableException].
  const CameraUnavailableException([String? message, Object? cause])
    : super(message ?? 'The camera could not be started.', cause: cause);
}

/// User denied camera permission.
class CameraPermissionDeniedException extends ScannerFailure {
  /// Creates a [CameraPermissionDeniedException].
  const CameraPermissionDeniedException([String? message])
    : super(
        message ??
            'Camera permission is denied. Enable camera access in device settings.',
      );
}

/// Capturing a photo or scanner page failed.
class CaptureFailedException extends ScannerFailure {
  /// Creates a [CaptureFailedException].
  const CaptureFailedException([Object? cause])
    : super('The page could not be captured. Please try again.', cause: cause);
}

/// Insufficient local storage space to store temporary scan images or PDF output.
class StorageFullException extends ScannerFailure {
  /// Creates a [StorageFullException].
  const StorageFullException([Object? cause])
    : super('Insufficient device storage to save scanned pages.', cause: cause);
}

/// Perspective crop validation or OpenCV warp failed.
class CropFailedException extends ScannerFailure {
  /// Creates a [CropFailedException].
  const CropFailedException([String? message, Object? cause])
    : super(
        message ??
            'The page could not be cropped. Adjust the corners and try again.',
        cause: cause,
      );
}

/// Generating or writing the local PDF document failed.
class PdfGenerationException extends ScannerFailure {
  /// Creates a [PdfGenerationException].
  const PdfGenerationException(super.message, {super.cause});
}
