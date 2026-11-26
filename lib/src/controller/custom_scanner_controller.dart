import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/capture_config.dart';
import '../config/custom_scanner_config.dart';
import '../config/pdf_config.dart';
import '../domain/crop_corners.dart';
import '../domain/crop_models.dart';
import '../domain/page_quality.dart';
import '../domain/scan_filter.dart';
import '../domain/scanned_page.dart';
import '../domain/scanned_pdf_result.dart';
import '../domain/scanner_failure.dart';
import '../infrastructure/camera/page_capture_service.dart';
import '../infrastructure/crop/document_detector.dart';
import '../infrastructure/crop/opencv_document_detector.dart';
import '../infrastructure/crop/opencv_perspective_cropper.dart';
import '../infrastructure/crop/perspective_cropper.dart';
import '../infrastructure/pdf/local_pdf_builder.dart';
import '../infrastructure/processing/opencv_page_processor.dart';
import '../infrastructure/processing/page_quality_evaluator.dart';
import '../infrastructure/storage/temp_scan_workspace.dart';

/// Stateful SDK controller managing the local reorderable scanned pages list,
/// single & multi-page batch OpenCV processing, "+ Add More" appending,
/// per-page/batch editing, and local PDF generation.
///
/// Host applications can either let `CustomPdfScanner.scan(...)` manage this
/// controller automatically or instantiate [CustomScannerController] directly
/// to embed `ScannedPagesReorderableView` (or custom UI) inside their own screens.
class CustomScannerController extends ChangeNotifier {
  /// Creates a [CustomScannerController] with customizable [config] and optional
  /// service overrides (useful for unit/widget testing).
  CustomScannerController({
    CustomScannerConfig config = const CustomScannerConfig(),
    DocumentDetector? detector,
    PerspectiveCropper? cropper,
    OpenCvPageProcessor? processor,
    LocalPdfBuilder? pdfBuilder,
    NativePageCaptureService? nativeCaptureService,
  }) : _config = config,
       _detectorOverride = detector,
       _cropperOverride = cropper,
       _processorOverride = processor,
       _pdfBuilderOverride = pdfBuilder,
       _nativeCapture = nativeCaptureService ?? const MlKitPageCaptureService();

  CustomScannerConfig _config;
  final DocumentDetector? _detectorOverride;
  final PerspectiveCropper? _cropperOverride;
  final OpenCvPageProcessor? _processorOverride;
  final LocalPdfBuilder? _pdfBuilderOverride;
  final NativePageCaptureService _nativeCapture;

  TempScanWorkspace? _workspace;
  final List<ScannedPage> _pages = <ScannedPage>[];

  bool _isProcessing = false;
  BatchProcessingProgress? _batchProgress;
  bool _isGeneratingPdf = false;
  PdfGenerationProgress? _pdfProgress;
  ScannerFailure? _lastError;
  bool _disposed = false;

  /// Current active configuration.
  CustomScannerConfig get config => _config;

  /// Updates the active [CustomScannerConfig] dynamically at runtime.
  void updateConfig(CustomScannerConfig newConfig) {
    _config = newConfig;
    _notifySafely();
  }

  /// Current ordered list of scanned & processed pages (`1..pageCount`).
  UnmodifiableListView<ScannedPage> get pages => UnmodifiableListView(_pages);

  /// Total number of pages currently in the local list.
  int get pageCount => _pages.length;

  /// True when the list currently has zero pages.
  bool get isEmpty => _pages.isEmpty;

  /// Remaining page capacity before hitting `CaptureConfig.maxPages`, or `null` if unlimited.
  int? get remainingPageSlots {
    final max = _config.capture.maxPages;
    if (max == null) return null;
    return (max - _pages.length).clamp(0, max);
  }

  /// True when additional pages can be added to the list.
  bool get canAddMore {
    if (!_config.pageList.allowAddMore && _pages.isNotEmpty) return false;
    final slots = remainingPageSlots;
    return slots == null || slots > 0;
  }

  /// True while OpenCV is cropping/enhancing one or more pages.
  bool get isProcessing => _isProcessing;

  /// Live progress of the active multi-page OpenCV batch, if [isProcessing] is `true`.
  BatchProcessingProgress? get batchProgress => _batchProgress;

  /// True while streaming pages into a local PDF file.
  bool get isGeneratingPdf => _isGeneratingPdf;

  /// Live progress of local PDF generation, if [isGeneratingPdf] is `true`.
  PdfGenerationProgress? get pdfProgress => _pdfProgress;

  /// True when either OpenCV processing or PDF generation is running.
  bool get isBusy => _isProcessing || _isGeneratingPdf;

  /// Most recent recoverable error, if any.
  ScannerFailure? get lastError => _lastError;

  /// Clears [lastError].
  void clearError() {
    _lastError = null;
    _notifySafely();
  }

  /// Looks up a [ScannedPage] by its [pageId].
  ScannedPage? pageById(String pageId) {
    for (final p in _pages) {
      if (p.id == pageId) return p;
    }
    return null;
  }

  DocumentDetector get _detector =>
      _detectorOverride ?? OpenCvDocumentDetector(config: _config.processing);

  PerspectiveCropper get _cropper =>
      _cropperOverride ??
      OpenCvPerspectiveCropper(useIsolate: _config.processing.useIsolate);

  OpenCvPageProcessor get _processor =>
      _processorOverride ?? OpenCvPageProcessor(config: _config.processing);

  PageQualityEvaluator get _qualityEvaluator =>
      PageQualityEvaluator(thresholds: _config.processing.qualityThresholds);

  LocalPdfBuilder get _pdfBuilder =>
      _pdfBuilderOverride ?? LocalPdfBuilder(config: _config.pdf);

  Future<TempScanWorkspace> _ensureWorkspace() async =>
      _workspace ??= await TempScanWorkspace.create(
        customBaseDirectory: _config.workingDirectoryPath,
      );

  /// Returns `true` if native ML Kit scanning should be used for [overrideBackend].
  bool shouldUseNativeMlKit([CaptureBackend? overrideBackend]) {
    final backend = overrideBackend ?? _config.capture.backend;
    return switch (backend) {
      CaptureBackend.mlKit => true,
      CaptureBackend.customCamera => false,
      CaptureBackend.auto => Platform.isAndroid,
    };
  }

  /// Launches native ML Kit capture (Android) in single-page or multi-page mode,
  /// processes all captured pages through OpenCV, and adds them to [pages].
  ///
  /// Returns the newly processed [ScannedPage] items (empty if the user cancelled).
  Future<List<ScannedPage>> captureAndProcessWithMlKit({
    ScanMode? modeOverride,
    String? replacePageId,
    int? insertAt,
    ScanFilter? filter,
  }) async {
    final mode = modeOverride ?? _config.capture.scanMode;
    final int limit;
    if (replacePageId != null || mode == ScanMode.singlePage) {
      limit = 1;
    } else {
      limit = remainingPageSlots ?? 200;
    }
    if (limit <= 0) return const [];

    final rawPages = await _nativeCapture.capturePages(
      pageLimit: limit,
      allowGalleryImport: _config.capture.allowGalleryImport,
    );
    if (rawPages.isEmpty) return const [];
    return addCapturedPages(
      rawPages,
      replacePageId: replacePageId,
      insertAt: insertAt,
      filter: filter,
    );
  }

  /// Imports arbitrary external image file paths (e.g. from gallery, file picker,
  /// or custom camera), processes them sequentially in batch through OpenCV
  /// (crop + enhance + thumbnail + quality), and appends/inserts them into [pages].
  Future<List<ScannedPage>> addImageFiles(
    List<String> imagePaths, {
    bool preCropped = false,
    int? insertAt,
    String? replacePageId,
    ScanFilter? filter,
  }) => addCapturedPages(
    [
      for (final path in imagePaths)
        CapturedRawPage(path: path, preCropped: preCropped),
    ],
    insertAt: insertAt,
    replacePageId: replacePageId,
    filter: filter,
  );

  /// Processes `1..N` [CapturedRawPage] items through the OpenCV pipeline and
  /// adds (or replaces) them in the local reorderable page list.
  Future<List<ScannedPage>> addCapturedPages(
    List<CapturedRawPage> rawPages, {
    int? insertAt,
    String? replacePageId,
    ScanFilter? filter,
  }) async {
    if (rawPages.isEmpty) return const [];

    final effectiveItems = replacePageId != null
        ? [rawPages.first]
        : _capToRemainingSlots(rawPages);
    if (effectiveItems.isEmpty) return const [];

    _isProcessing = true;
    _lastError = null;
    _batchProgress = BatchProcessingProgress(
      completed: 0,
      total: effectiveItems.length,
      currentIndex: 1,
    );
    _notifySafely();

    final ws = await _ensureWorkspace();
    final chosenFilter = filter ?? _config.processing.defaultFilter;
    final createdPages = <ScannedPage>[];

    try {
      for (var i = 0; i < effectiveItems.length; i++) {
        _batchProgress = BatchProcessingProgress(
          completed: i,
          total: effectiveItems.length,
          currentIndex: i + 1,
          latestPage: createdPages.isEmpty ? null : createdPages.last,
        );
        _notifySafely();

        final raw = effectiveItems[i];
        final page = await _processSingleRawCapture(
          ws: ws,
          raw: raw,
          filter: chosenFilter,
        );
        createdPages.add(page);

        if (replacePageId != null) {
          final existingIndex = _pages.indexWhere((p) => p.id == replacePageId);
          if (existingIndex >= 0) {
            final oldPage = _pages[existingIndex];
            _pages[existingIndex] = page.copyWith(
              pageNumber: existingIndex + 1,
            );
            await ws.deletePageFiles(oldPage.id);
          } else {
            _pages.add(page);
          }
        } else if (insertAt != null) {
          final targetIdx = (insertAt + i).clamp(0, _pages.length);
          _pages.insert(targetIdx, page);
        } else {
          _pages.add(page);
        }
        _renumberPages();

        _batchProgress = BatchProcessingProgress(
          completed: i + 1,
          total: effectiveItems.length,
          currentIndex: i + 1,
          latestPage: _pages.firstWhere((p) => p.id == page.id),
        );
        _notifySafely();
      }
      return [
        for (final p in createdPages)
          _pages.firstWhere((item) => item.id == p.id, orElse: () => p),
      ];
    } on ScannerFailure catch (e) {
      _lastError = e;
      rethrow;
    } on Object catch (e) {
      final wrapped = CaptureFailedException(e);
      _lastError = wrapped;
      throw wrapped;
    } finally {
      _isProcessing = false;
      _batchProgress = null;
      _notifySafely();
    }
  }

  List<CapturedRawPage> _capToRemainingSlots(List<CapturedRawPage> items) {
    final slots = remainingPageSlots;
    if (slots == null) return items;
    if (slots <= 0) return const [];
    return items.length <= slots ? items : items.sublist(0, slots);
  }

  Future<ScannedPage> _processSingleRawCapture({
    required TempScanWorkspace ws,
    required CapturedRawPage raw,
    required ScanFilter filter,
  }) async {
    final pageId = ws.nextPageId();
    final originalPath = await ws.importOriginal(pageId, raw.path);
    final (origW, origH) = await _cropper.imageSize(originalPath);

    CropCorners corners;
    CropSource cropSource;
    double? confidence;

    if (raw.preCropped) {
      corners = CropCorners.full(origW, origH);
      cropSource = CropSource.preCropped;
      confidence = 1.0;
    } else if (_config.processing.autoCrop) {
      final detection = await _detector.detectFile(originalPath);
      confidence = detection.confidence;
      if (detection.isConfident && detection.corners != null) {
        corners = detection.corners!.withMargin(
          _config.processing.cropSafetyMargin,
          origW,
          origH,
        );
        cropSource = CropSource.auto;
      } else {
        corners = CropCorners.full(origW, origH);
        cropSource = CropSource.fullImage;
      }
    } else {
      corners = CropCorners.full(origW, origH);
      cropSource = CropSource.fullImage;
    }

    final croppedPath = ws.nextCroppedPath(pageId);
    final cropOut = await _cropper.crop(
      originalPath: originalPath,
      corners: corners,
      quarterTurns: 0,
      outputPath: croppedPath,
      maxLongEdge: _config.processing.maxLongEdge,
      jpegQuality: _config.processing.croppedJpegQuality,
    );

    final processedTarget = ws.nextProcessedPath(pageId, filter);
    final thumbTarget = ws.nextThumbnailPath(pageId);
    final enhanced = await _processor.processPage(
      croppedPath: croppedPath,
      filter: filter,
      outputPath: processedTarget,
      thumbnailOutputPath: thumbTarget,
    );

    final quality = _evaluateQuality(
      enhanced: enhanced,
      corners: corners,
      origW: origW,
      origH: origH,
      cropSource: cropSource,
      filter: filter,
    );

    return ScannedPage(
      id: pageId,
      pageNumber: _pages.length + 1,
      originalPath: originalPath,
      croppedPath: croppedPath,
      processedPath: enhanced.outputPath,
      thumbnailPath: enhanced.thumbnailWritten ? thumbTarget : null,
      originalWidth: origW,
      originalHeight: origH,
      width: enhanced.width > 0 ? enhanced.width : cropOut.width,
      height: enhanced.height > 0 ? enhanced.height : cropOut.height,
      corners: corners,
      cropSource: cropSource,
      cropConfidence: confidence,
      rotationQuarterTurns: 0,
      filter: filter,
      quality: quality,
      usedFallback: enhanced.usedFallback,
      checksum: enhanced.checksum,
      byteLength: enhanced.byteLength,
      capturedAt: DateTime.now(),
    );
  }

  PageQuality _evaluateQuality({
    required PageEnhancementResult enhanced,
    required CropCorners corners,
    required int origW,
    required int origH,
    required CropSource cropSource,
    required ScanFilter filter,
  }) {
    if (!_config.processing.enableQualityChecks) return PageQuality.clean;
    final capQ = enhanced.captureMetrics.isEmpty
        ? PageQuality.clean
        : _qualityEvaluator.assessCapture(
            enhanced.captureMetrics,
            corners: corners,
            imageWidth: origW,
            imageHeight: origH,
            source: cropSource,
          );
    final outQ = enhanced.outputMetrics.isEmpty
        ? PageQuality.clean
        : _qualityEvaluator.assessOutput(enhanced.outputMetrics, filter);
    return capQ.merge(outQ);
  }

  // ---------------------------------------------------------------------------
  // Reorderable List Management
  // ---------------------------------------------------------------------------

  /// Reorders pages using standard Flutter `ReorderableListView.onReorder`
  /// index semantics (`if (newIndex > oldIndex) newIndex -= 1`).
  void reorder(int oldIndex, int newIndex) {
    if (!_config.pageList.enableReorder) return;
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    movePage(oldIndex, target);
  }

  /// Moves the page at [fromIndex] directly to [toIndex] (`0..pageCount - 1`).
  void movePage(int fromIndex, int toIndex) {
    if (!_config.pageList.enableReorder) return;
    if (fromIndex < 0 || fromIndex >= _pages.length) return;
    final clampedTo = toIndex.clamp(0, _pages.length - 1);
    if (fromIndex == clampedTo) return;
    final item = _pages.removeAt(fromIndex);
    _pages.insert(clampedTo, item);
    _renumberPages();
    _notifySafely();
  }

  /// Removes the page with [pageId] from the list and deletes its temp files.
  Future<void> removePage(String pageId) async {
    final idx = _pages.indexWhere((p) => p.id == pageId);
    if (idx < 0) return;
    final removed = _pages.removeAt(idx);
    _renumberPages();
    _notifySafely();
    await _workspace?.deletePageFiles(removed.id);
  }

  /// Removes all pages and cleans up temporary page files.
  Future<void> clearAll() async {
    _pages.clear();
    _lastError = null;
    _notifySafely();
    final oldWs = _workspace;
    _workspace = null;
    await oldWs?.dispose();
  }

  void _renumberPages() {
    for (var i = 0; i < _pages.length; i++) {
      if (_pages[i].pageNumber != i + 1) {
        _pages[i] = _pages[i].copyWith(pageNumber: i + 1);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Per-Page & Batch Editing (Re-crop, Rotate, Filter)
  // ---------------------------------------------------------------------------

  /// Runs OpenCV boundary detection on [pageId]'s original image (useful for
  /// an "Auto-Detect Corners" action inside the manual crop screen).
  Future<DetectionResult> detectCornersForPage(String pageId) async {
    final page = pageById(pageId);
    if (page == null) {
      throw StateError('Page $pageId not found');
    }
    return _detector.detectFile(page.originalPath);
  }

  /// Applies a new [ScanFilter] to [pageId], always re-enhancing from
  /// `croppedPath` so filters never compound JPEG compression artifacts.
  Future<ScannedPage> applyFilter(String pageId, ScanFilter filter) async {
    final idx = _pages.indexWhere((p) => p.id == pageId);
    if (idx < 0) throw StateError('Page $pageId not found');

    _isProcessing = true;
    _notifySafely();
    try {
      final ws = await _ensureWorkspace();
      final current = _pages[idx];
      final processedTarget = ws.nextProcessedPath(pageId, filter);
      final thumbTarget = ws.nextThumbnailPath(pageId);
      final enhanced = await _processor.processPage(
        croppedPath: current.croppedPath,
        filter: filter,
        outputPath: processedTarget,
        thumbnailOutputPath: thumbTarget,
      );
      final quality = _evaluateQuality(
        enhanced: enhanced,
        corners:
            current.corners ??
            CropCorners.full(current.originalWidth, current.originalHeight),
        origW: current.originalWidth,
        origH: current.originalHeight,
        cropSource: current.cropSource,
        filter: filter,
      );
      final updated = current.copyWith(
        filter: filter,
        processedPath: enhanced.outputPath,
        thumbnailPath: enhanced.thumbnailWritten
            ? thumbTarget
            : current.thumbnailPath,
        width: enhanced.width > 0 ? enhanced.width : current.width,
        height: enhanced.height > 0 ? enhanced.height : current.height,
        quality: quality,
        usedFallback: enhanced.usedFallback,
        checksum: enhanced.checksum,
        byteLength: enhanced.byteLength,
      );
      _pages[idx] = updated;
      return updated;
    } finally {
      _isProcessing = false;
      _notifySafely();
    }
  }

  /// Batch-applies [filter] across **every** page in [pages], reporting live
  /// [batchProgress] along the way.
  Future<void> applyFilterToAll(ScanFilter filter) async {
    if (_pages.isEmpty) return;
    _isProcessing = true;
    _batchProgress = BatchProcessingProgress(
      completed: 0,
      total: _pages.length,
      currentIndex: 1,
    );
    _notifySafely();

    try {
      final ws = await _ensureWorkspace();
      for (var i = 0; i < _pages.length; i++) {
        final current = _pages[i];
        _batchProgress = BatchProcessingProgress(
          completed: i,
          total: _pages.length,
          currentIndex: i + 1,
        );
        _notifySafely();

        final processedTarget = ws.nextProcessedPath(current.id, filter);
        final thumbTarget = ws.nextThumbnailPath(current.id);
        final enhanced = await _processor.processPage(
          croppedPath: current.croppedPath,
          filter: filter,
          outputPath: processedTarget,
          thumbnailOutputPath: thumbTarget,
        );
        final quality = _evaluateQuality(
          enhanced: enhanced,
          corners:
              current.corners ??
              CropCorners.full(current.originalWidth, current.originalHeight),
          origW: current.originalWidth,
          origH: current.originalHeight,
          cropSource: current.cropSource,
          filter: filter,
        );
        final updated = current.copyWith(
          filter: filter,
          processedPath: enhanced.outputPath,
          thumbnailPath: enhanced.thumbnailWritten
              ? thumbTarget
              : current.thumbnailPath,
          width: enhanced.width > 0 ? enhanced.width : current.width,
          height: enhanced.height > 0 ? enhanced.height : current.height,
          quality: quality,
          usedFallback: enhanced.usedFallback,
          checksum: enhanced.checksum,
          byteLength: enhanced.byteLength,
        );
        _pages[i] = updated;

        _batchProgress = BatchProcessingProgress(
          completed: i + 1,
          total: _pages.length,
          currentIndex: i + 1,
          latestPage: updated,
        );
        _notifySafely();
      }
    } finally {
      _isProcessing = false;
      _batchProgress = null;
      _notifySafely();
    }
  }

  /// Rotates [pageId] clockwise by [clockwiseQuarterTurns] (`90° × turns`),
  /// re-cropping cleanly from `originalPath` and re-applying its active filter.
  Future<ScannedPage> rotatePage(
    String pageId, {
    int clockwiseQuarterTurns = 1,
  }) async {
    final current = pageById(pageId);
    if (current == null) throw StateError('Page $pageId not found');
    final nextTurns =
        (current.rotationQuarterTurns + clockwiseQuarterTurns) % 4;
    return updatePageCrop(
      pageId,
      corners:
          current.corners ??
          CropCorners.full(current.originalWidth, current.originalHeight),
      rotationQuarterTurns: nextTurns,
      cropSource: current.cropSource,
    );
  }

  /// Re-warps [pageId] from `originalPath` using manual/adjusted [corners] and
  /// [rotationQuarterTurns], then re-applies its active [ScanFilter].
  Future<ScannedPage> updatePageCrop(
    String pageId, {
    required CropCorners corners,
    int? rotationQuarterTurns,
    CropSource cropSource = CropSource.manual,
  }) async {
    final idx = _pages.indexWhere((p) => p.id == pageId);
    if (idx < 0) throw StateError('Page $pageId not found');
    final current = _pages[idx];

    if (!corners.isConvex || corners.minAngle < 25) {
      throw const CropFailedException(
        'Selected corners form an invalid shape. Keep all 4 corners uncrossed.',
      );
    }

    _isProcessing = true;
    _notifySafely();
    try {
      final ws = await _ensureWorkspace();
      final turns = (rotationQuarterTurns ?? current.rotationQuarterTurns) % 4;
      final croppedTarget = ws.nextCroppedPath(pageId);
      final cropOut = await _cropper.crop(
        originalPath: current.originalPath,
        corners: corners,
        quarterTurns: turns,
        outputPath: croppedTarget,
        maxLongEdge: _config.processing.maxLongEdge,
        jpegQuality: _config.processing.croppedJpegQuality,
      );

      final processedTarget = ws.nextProcessedPath(pageId, current.filter);
      final thumbTarget = ws.nextThumbnailPath(pageId);
      final enhanced = await _processor.processPage(
        croppedPath: croppedTarget,
        filter: current.filter,
        outputPath: processedTarget,
        thumbnailOutputPath: thumbTarget,
      );
      final quality = _evaluateQuality(
        enhanced: enhanced,
        corners: corners,
        origW: current.originalWidth,
        origH: current.originalHeight,
        cropSource: cropSource,
        filter: current.filter,
      );

      final updated = current.copyWith(
        croppedPath: croppedTarget,
        processedPath: enhanced.outputPath,
        thumbnailPath: enhanced.thumbnailWritten
            ? thumbTarget
            : current.thumbnailPath,
        width: enhanced.width > 0 ? enhanced.width : cropOut.width,
        height: enhanced.height > 0 ? enhanced.height : cropOut.height,
        corners: corners,
        cropSource: cropSource,
        rotationQuarterTurns: turns,
        quality: quality,
        usedFallback: enhanced.usedFallback,
        checksum: enhanced.checksum,
        byteLength: enhanced.byteLength,
      );
      _pages[idx] = updated;
      return updated;
    } finally {
      _isProcessing = false;
      _notifySafely();
    }
  }

  // ---------------------------------------------------------------------------
  // Local PDF Generation
  // ---------------------------------------------------------------------------

  /// Streams all [pages] in their current order into a local `.pdf` file and
  /// returns [ScannedPdfResult].
  Future<ScannedPdfResult> generatePdf({
    String? outputFilePath,
    PdfConfig? overridePdfConfig,
  }) async {
    if (_pages.isEmpty) {
      throw const PdfGenerationException(
        'Add at least one page before generating a PDF.',
      );
    }

    final effectivePdf = overridePdfConfig ?? _config.pdf;
    final ws = await _ensureWorkspace();
    final targetPath = await ws.resolvePdfOutputPath(
      outputDirectoryPath: effectivePdf.outputDirectoryPath,
      customOutputFilePath: outputFilePath ?? effectivePdf.customOutputFilePath,
      fileNamePrefix: effectivePdf.fileNamePrefix,
    );

    _isGeneratingPdf = true;
    _lastError = null;
    _pdfProgress = PdfGenerationProgress(
      completedPages: 0,
      totalPages: _pages.length,
    );
    _notifySafely();

    try {
      final snapshot = List<ScannedPage>.unmodifiable(_pages);
      final result = await _pdfBuilder.buildFromScannedPages(
        pages: snapshot,
        outputFilePath: targetPath,
        overrideConfig: effectivePdf,
        onProgress: (p) {
          _pdfProgress = p;
          _notifySafely();
        },
      );

      if (effectivePdf.deleteTempFilesAfterExport) {
        final oldWs = _workspace;
        _workspace = null;
        await oldWs?.dispose();
      }
      return result;
    } on ScannerFailure catch (e) {
      _lastError = e;
      rethrow;
    } on Object catch (e) {
      final wrapped = PdfGenerationException(
        'Could not generate local PDF: $e',
        cause: e,
      );
      _lastError = wrapped;
      throw wrapped;
    } finally {
      _isGeneratingPdf = false;
      _pdfProgress = null;
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  /// Disposes this controller and optionally deletes temporary workspace files.
  Future<void> disposeWorkspaceAndController({
    bool deleteTempFiles = false,
  }) async {
    if (deleteTempFiles) {
      final ws = _workspace;
      _workspace = null;
      await ws?.dispose();
    }
    if (!_disposed) {
      _disposed = true;
      super.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
