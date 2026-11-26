import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/scan_filter.dart';

/// Isolated local disk workspace holding originals, perspective crops,
/// OpenCV-processed outputs, and thumbnails for one `CustomScannerController`
/// session.
///
/// Every file mutation generates a unique revision suffix so Flutter's
/// `FileImage` cache never serves stale pixels after re-cropping or rotating.
class TempScanWorkspace {
  TempScanWorkspace._(this.rootPath);

  /// Absolute directory path of this session's local workspace.
  final String rootPath;

  int _counter = 0;

  static Future<String> _resolveBaseDir(String? customDir) async {
    if (customDir != null && customDir.isNotEmpty) return customDir;
    try {
      return (await getTemporaryDirectory()).path;
    } on Object {
      return Directory.systemTemp.path;
    }
  }

  /// Creates and initializes a fresh local workspace directory.
  static Future<TempScanWorkspace> create({String? customBaseDirectory}) async {
    final base = await _resolveBaseDir(customBaseDirectory);
    final sessionId =
        'scan_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(999999)}';
    final root = p.join(base, 'custom_pdf_scanner', sessionId);
    for (final sub in const [
      'originals',
      'cropped',
      'processed',
      'thumbnails',
    ]) {
      await Directory(p.join(root, sub)).create(recursive: true);
    }
    return TempScanWorkspace._(root);
  }

  /// Generates a unique page ID within this workspace.
  String nextPageId() =>
      'p_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  String _rev() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Copies or moves an incoming captured/imported image into `originals/`.
  Future<String> importOriginal(
    String pageId,
    String sourcePath, {
    bool move = false,
  }) async {
    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath)
        : '.jpg';
    final dest = p.join(rootPath, 'originals', '$pageId$ext');
    await File(dest).parent.create(recursive: true);
    if (move) {
      try {
        await File(sourcePath).rename(dest);
        return dest;
      } on FileSystemException {
        // Cross-volume fallback.
      }
    }
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// Fresh output path for a perspective-cropped JPEG.
  String nextCroppedPath(String pageId) =>
      p.join(rootPath, 'cropped', '${pageId}_${_rev()}.jpg');

  /// Fresh output path for an OpenCV-enhanced page.
  String nextProcessedPath(String pageId, ScanFilter filter) => p.join(
    rootPath,
    'processed',
    '${pageId}_${_rev()}.${filter.fileExtension}',
  );

  /// Fresh output path for a 240px list/grid thumbnail JPEG.
  String nextThumbnailPath(String pageId) =>
      p.join(rootPath, 'thumbnails', '${pageId}_${_rev()}.jpg');

  /// Resolves the output `.pdf` path when `PdfConfig.customOutputFilePath` is null.
  Future<String> resolvePdfOutputPath({
    String? outputDirectoryPath,
    String? customOutputFilePath,
    String fileNamePrefix = 'scan_',
  }) async {
    if (customOutputFilePath != null && customOutputFilePath.isNotEmpty) {
      await File(customOutputFilePath).parent.create(recursive: true);
      return customOutputFilePath;
    }
    final dir = await _resolveBaseDir(outputDirectoryPath);
    await Directory(dir).create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir, '$fileNamePrefix$stamp.pdf');
  }

  /// Deletes all files belonging to a specific [pageId].
  Future<void> deletePageFiles(String pageId) async {
    for (final sub in const [
      'originals',
      'cropped',
      'processed',
      'thumbnails',
    ]) {
      final dir = Directory(p.join(rootPath, sub));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (name == pageId ||
            name.startsWith('$pageId.') ||
            name.startsWith('${pageId}_')) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Best-effort cleanup.
          }
        }
      }
    }
  }

  /// Deletes the entire temporary workspace directory.
  Future<void> dispose() async {
    final dir = Directory(rootPath);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }
}
