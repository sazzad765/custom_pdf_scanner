import 'dart:convert';
import 'dart:io';

import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Metadata for a locally generated PDF saved in the example app's history.
class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.id,
    required this.title,
    required this.pdfPath,
    required this.pageCount,
    required this.byteLength,
    required this.createdAt,
    required this.scanModeLabel,
    required this.filterLabel,
    required this.pageSizeLabel,
    this.coverImagePath,
    this.sha256,
  });

  factory ScanHistoryEntry.fromJson(Map<String, Object?> json) =>
      ScanHistoryEntry(
        id: json['id']! as String,
        title: json['title']! as String,
        pdfPath: json['pdfPath']! as String,
        pageCount: (json['pageCount']! as num).toInt(),
        byteLength: (json['byteLength']! as num).toInt(),
        createdAt: DateTime.parse(json['createdAt']! as String),
        scanModeLabel: json['scanModeLabel'] as String? ?? 'Multi-Page',
        filterLabel: json['filterLabel'] as String? ?? 'Magic Color',
        pageSizeLabel: json['pageSizeLabel'] as String? ?? 'Fit',
        coverImagePath: json['coverImagePath'] as String?,
        sha256: json['sha256'] as String?,
      );

  final String id;
  final String title;
  final String pdfPath;
  final int pageCount;
  final int byteLength;
  final DateTime createdAt;
  final String scanModeLabel;
  final String filterLabel;
  final String pageSizeLabel;
  final String? coverImagePath;
  final String? sha256;

  ScanHistoryEntry copyWith({String? title}) => ScanHistoryEntry(
    id: id,
    title: title ?? this.title,
    pdfPath: pdfPath,
    pageCount: pageCount,
    byteLength: byteLength,
    createdAt: createdAt,
    scanModeLabel: scanModeLabel,
    filterLabel: filterLabel,
    pageSizeLabel: pageSizeLabel,
    coverImagePath: coverImagePath,
    sha256: sha256,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'pdfPath': pdfPath,
    'pageCount': pageCount,
    'byteLength': byteLength,
    'createdAt': createdAt.toIso8601String(),
    'scanModeLabel': scanModeLabel,
    'filterLabel': filterLabel,
    'pageSizeLabel': pageSizeLabel,
    'coverImagePath': coverImagePath,
    'sha256': sha256,
  };
}

/// Persistent local store for generated PDFs and their cover thumbnails.
class ScanHistoryStore extends ChangeNotifier {
  final List<ScanHistoryEntry> _entries = <ScanHistoryEntry>[];
  String? _pdfsDir;
  String? _thumbsDir;
  String? _indexFilePath;
  bool _loaded = false;

  List<ScanHistoryEntry> get entries => List.unmodifiable(_entries);
  bool get isLoaded => _loaded;
  String? get pdfsDirectoryPath => _pdfsDir;

  Future<void> init() async {
    if (_loaded) return;
    final docs = await getApplicationDocumentsDirectory();
    final root = p.join(docs.path, 'scanner_example_history');
    _pdfsDir = p.join(root, 'pdfs');
    _thumbsDir = p.join(root, 'thumbs');
    _indexFilePath = p.join(root, 'history.json');

    await Directory(_pdfsDir!).create(recursive: true);
    await Directory(_thumbsDir!).create(recursive: true);

    final indexFile = File(_indexFilePath!);
    if (await indexFile.exists()) {
      try {
        final raw = jsonDecode(await indexFile.readAsString()) as List<Object?>;
        for (final item in raw) {
          final entry = ScanHistoryEntry.fromJson(
            item! as Map<String, Object?>,
          );
          if (await File(entry.pdfPath).exists()) {
            _entries.add(entry);
          }
        }
      } on Object {
        // Ignore corrupted demo cache.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<ScanHistoryEntry> recordScan({
    required ScannedPdfResult result,
    required String scanModeLabel,
    required String filterLabel,
    required String pageSizeLabel,
  }) async {
    await init();
    final now = DateTime.now();
    final id = 'doc_${now.microsecondsSinceEpoch}';

    // Ensure the PDF lives inside the persistent history folder.
    var finalPdfPath = result.pdfPath;
    if (!p.isWithin(_pdfsDir!, result.pdfPath)) {
      final destPdf = p.join(_pdfsDir!, '$id.pdf');
      await File(result.pdfPath).copy(destPdf);
      finalPdfPath = destPdf;
    }

    // Persist a lightweight cover thumbnail from page 1 if available.
    String? coverPath;
    if (result.pages.isNotEmpty) {
      final firstPreview = result.pages.first.listPreviewPath;
      if (await File(firstPreview).exists()) {
        final ext = p.extension(firstPreview).isNotEmpty
            ? p.extension(firstPreview)
            : '.jpg';
        final destThumb = p.join(_thumbsDir!, '$id$ext');
        try {
          await File(firstPreview).copy(destThumb);
          coverPath = destThumb;
        } on Object {
          coverPath = null;
        }
      }
    }

    String two(int n) => n.toString().padLeft(2, '0');
    final defaultTitle =
        'Scan ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';

    final entry = ScanHistoryEntry(
      id: id,
      title: defaultTitle,
      pdfPath: finalPdfPath,
      pageCount: result.pageCount,
      byteLength: result.byteLength,
      createdAt: now,
      scanModeLabel: scanModeLabel,
      filterLabel: filterLabel,
      pageSizeLabel: pageSizeLabel,
      coverImagePath: coverPath,
      sha256: result.sha256,
    );

    _entries.insert(0, entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<void> rename(String id, String newTitle) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    _entries[idx] = _entries[idx].copyWith(title: trimmed);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final removed = _entries.removeAt(idx);
    await _persist();
    notifyListeners();

    await _tryDeleteFile(removed.pdfPath);
    if (removed.coverImagePath != null) {
      await _tryDeleteFile(removed.coverImagePath!);
    }
  }

  Future<void> clearAll() async {
    final snapshot = [..._entries];
    _entries.clear();
    await _persist();
    notifyListeners();

    for (final item in snapshot) {
      await _tryDeleteFile(item.pdfPath);
      if (item.coverImagePath != null) {
        await _tryDeleteFile(item.coverImagePath!);
      }
    }
  }

  Future<void> _persist() async {
    final path = _indexFilePath;
    if (path == null) return;
    final data = jsonEncode([for (final e in _entries) e.toJson()]);
    await File(path).writeAsString(data, flush: true);
  }

  static Future<void> _tryDeleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } on Object {
        // Ignore cleanup failure.
      }
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
