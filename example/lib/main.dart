import 'dart:async';
import 'dart:io';

import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/material.dart';

import 'pdf_preview_screen.dart';
import 'scan_history_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScannerExampleApp());
}

class ScannerExampleApp extends StatelessWidget {
  const ScannerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'custom_pdf_scanner Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F766E),
        useMaterial3: true,
      ),
      home: const ScannerPlaygroundPage(),
    );
  }
}

class ScannerPlaygroundPage extends StatefulWidget {
  const ScannerPlaygroundPage({super.key});

  @override
  State<ScannerPlaygroundPage> createState() => _ScannerPlaygroundPageState();
}

class _ScannerPlaygroundPageState extends State<ScannerPlaygroundPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScanHistoryStore _historyStore = ScanHistoryStore();

  ScanMode _scanMode = ScanMode.multiPage;
  SinglePageBehavior _singleBehavior = SinglePageBehavior.reviewThenPdf;
  CaptureBackend _backend = CaptureBackend.auto;
  ScanFilter _defaultFilter = ScanFilter.magicColor;
  ScanQualityPreset _qualityPreset = ScanQualityPreset.balanced;
  PdfPageSize _pdfPageSize = PdfPageSize.fitToImage;
  bool _autoOpenPreview = true;

  ScanHistoryEntry? _latestEntry;
  late final CustomScannerController _embeddedController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _embeddedController = CustomScannerController(config: _buildConfig());
    _historyStore.addListener(_onHistoryChanged);
    unawaited(_initHistory());
  }

  Future<void> _initHistory() async {
    await _historyStore.init();
    if (mounted && _historyStore.entries.isNotEmpty) {
      setState(() => _latestEntry = _historyStore.entries.first);
    }
  }

  @override
  void dispose() {
    _historyStore.removeListener(_onHistoryChanged);
    _historyStore.dispose();
    _embeddedController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (!mounted) return;
    setState(() {
      _latestEntry = _historyStore.entries.isEmpty
          ? null
          : _historyStore.entries.first;
    });
  }

  CustomScannerConfig _buildConfig() => CustomScannerConfig(
    capture: CaptureConfig(
      scanMode: _scanMode,
      singlePageBehavior: _singleBehavior,
      backend: _backend,
      maxPages: 100,
    ),
    processing: ProcessingConfig.fromPreset(
      _qualityPreset,
      defaultFilter: _defaultFilter,
    ),
    pdf: PdfConfig(
      outputDirectoryPath: _historyStore.pdfsDirectoryPath,
      pageSize: _pdfPageSize,
      marginsPt: _pdfPageSize.isFitToImage
          ? EdgeInsets.zero
          : const EdgeInsets.all(20),
      metadata: const PdfDocumentMetadata(title: 'Demo Scan'),
    ),
  );

  Future<void> _handleCompletedScan(
    ScannedPdfResult result, {
    required String modeLabel,
  }) async {
    final entry = await _historyStore.recordScan(
      result: result,
      scanModeLabel: modeLabel,
      filterLabel: _defaultFilter.defaultLabel,
      pageSizeLabel: _pdfPageSize.name.toUpperCase(),
    );
    if (!mounted) return;
    setState(() => _latestEntry = entry);
    if (_autoOpenPreview) {
      await _openPreview(entry);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${entry.title}" (${entry.pageCount} pages)'),
          action: SnackBarAction(
            label: 'Preview',
            onPressed: () => _openPreview(entry),
          ),
        ),
      );
    }
  }

  Future<void> _openPreview(ScanHistoryEntry entry) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            PdfPreviewScreen(entry: entry, historyStore: _historyStore),
      ),
    );
  }

  Future<void> _launchModalScanner() async {
    await _historyStore.init();
    if (!mounted) return;
    final result = await CustomPdfScanner.scan(context, config: _buildConfig());
    if (result != null && mounted) {
      await _handleCompletedScan(
        result,
        modeLabel: _scanMode == ScanMode.singlePage
            ? 'Single Page'
            : 'Multi-Page',
      );
    }
  }

  Future<void> _embeddedScan(ScanMode mode) async {
    await _historyStore.init();
    _embeddedController.updateConfig(_buildConfig());
    if (_embeddedController.shouldUseNativeMlKit()) {
      await _embeddedController.captureAndProcessWithMlKit(modeOverride: mode);
    } else {
      if (!mounted) return;
      final raw = await Navigator.of(context).push<List<CapturedRawPage>>(
        MaterialPageRoute(
          builder: (_) => MultiShotCameraScreen(
            config: _embeddedController.config,
            scanMode: mode,
          ),
        ),
      );
      if (raw != null && raw.isNotEmpty) {
        await _embeddedController.addCapturedPages(raw);
      }
    }
  }

  Future<void> _embeddedGeneratePdf() async {
    await _historyStore.init();
    _embeddedController.updateConfig(_buildConfig());
    final res = await _embeddedController.generatePdf();
    if (mounted) {
      await _handleCompletedScan(res, modeLabel: 'Embedded List');
    }
  }

  Future<void> _renameEntryDialog(ScanHistoryEntry entry) async {
    final textCtrl = TextEditingController(text: entry.title);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document Title'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    if (updated != null && updated.trim().isNotEmpty) {
      await _historyStore.rename(entry.id, updated);
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all scan history?'),
        content: const Text(
          'This will permanently delete all saved demo PDFs from history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyStore.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyCount = _historyStore.entries.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('custom_pdf_scanner SDK'),
        actions: [
          if (_tabController.index == 2 && historyCount > 0)
            IconButton(
              tooltip: 'Clear History',
              onPressed: _confirmClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: '1. Launcher'),
            const Tab(text: '2. Embedded'),
            Tab(
              text: historyCount == 0
                  ? '3. History'
                  : '3. History ($historyCount)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLauncherTab(),
          _buildEmbeddedTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildLauncherTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<ScanMode>(
          initialValue: _scanMode,
          decoration: const InputDecoration(labelText: 'Scan Mode'),
          items: const [
            DropdownMenuItem(
              value: ScanMode.multiPage,
              child: Text('Multi-Page Batch -> Reorderable List'),
            ),
            DropdownMenuItem(
              value: ScanMode.singlePage,
              child: Text('Single Page'),
            ),
          ],
          onChanged: (v) => setState(() => _scanMode = v!),
        ),
        if (_scanMode == ScanMode.singlePage) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<SinglePageBehavior>(
            initialValue: _singleBehavior,
            decoration: const InputDecoration(
              labelText: 'Single-Page Behavior',
            ),
            items: const [
              DropdownMenuItem(
                value: SinglePageBehavior.reviewThenPdf,
                child: Text('Review / Filter -> PDF'),
              ),
              DropdownMenuItem(
                value: SinglePageBehavior.immediatePdf,
                child: Text('Immediate Auto PDF'),
              ),
              DropdownMenuItem(
                value: SinglePageBehavior.addToPageList,
                child: Text('Add to Reorderable List'),
              ),
            ],
            onChanged: (v) => setState(() => _singleBehavior = v!),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<CaptureBackend>(
          initialValue: _backend,
          decoration: const InputDecoration(labelText: 'Capture Backend'),
          items: const [
            DropdownMenuItem(
              value: CaptureBackend.auto,
              child: Text('Auto (ML Kit on Android, OpenCV Camera on iOS)'),
            ),
            DropdownMenuItem(
              value: CaptureBackend.customCamera,
              child: Text('Built-in OpenCV Live Camera (Android & iOS)'),
            ),
            DropdownMenuItem(
              value: CaptureBackend.mlKit,
              child: Text('Google ML Kit Scanner (Android)'),
            ),
          ],
          onChanged: (v) => setState(() => _backend = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ScanFilter>(
          initialValue: _defaultFilter,
          decoration: const InputDecoration(labelText: 'Default OpenCV Filter'),
          items: [
            for (final f in ScanFilter.values)
              DropdownMenuItem(value: f, child: Text(f.defaultLabel)),
          ],
          onChanged: (v) => setState(() => _defaultFilter = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ScanQualityPreset>(
          initialValue: _qualityPreset,
          decoration: const InputDecoration(labelText: 'Resolution & Quality'),
          items: [
            for (final q in ScanQualityPreset.values)
              DropdownMenuItem(value: q, child: Text(q.name.toUpperCase())),
          ],
          onChanged: (v) => setState(() => _qualityPreset = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PdfPageSize>(
          initialValue: _pdfPageSize,
          decoration: const InputDecoration(labelText: 'PDF Page Size'),
          items: const [
            DropdownMenuItem(
              value: PdfPageSize.fitToImage,
              child: Text('Fit to Scanned Page'),
            ),
            DropdownMenuItem(value: PdfPageSize.a4, child: Text('ISO A4')),
            DropdownMenuItem(
              value: PdfPageSize.letter,
              child: Text('US Letter'),
            ),
          ],
          onChanged: (v) => setState(() => _pdfPageSize = v!),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Open PDF Preview immediately after scan'),
          value: _autoOpenPreview,
          onChanged: (v) => setState(() => _autoOpenPreview = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _launchModalScanner,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Launch CustomPdfScanner.scan()'),
        ),
        if (_latestEntry != null) ...[
          const SizedBox(height: 20),
          _buildHistoryCard(_latestEntry!, isLatestHighlight: true),
        ],
      ],
    );
  }

  Widget _buildEmbeddedTab() {
    return ListenableBuilder(
      listenable: _embeddedController,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(
              child: ScannedPagesReorderableView(
                controller: _embeddedController,
                onStartScan: () => _embeddedScan(ScanMode.multiPage),
                onPageTap: (page) {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PageEditorScreen(
                        controller: _embeddedController,
                        pageId: page.id,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _embeddedController.isBusy
                        ? null
                        : () => _embeddedScan(ScanMode.singlePage),
                    icon: const Icon(Icons.add),
                    label: const Text('+1 Page'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _embeddedController.isBusy
                        ? null
                        : () => _embeddedScan(ScanMode.multiPage),
                    icon: const Icon(Icons.burst_mode_outlined),
                    label: const Text('+Multi'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _embeddedController.isEmpty ||
                              _embeddedController.isBusy
                          ? null
                          : _embeddedGeneratePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(
                        'Save & Preview (${_embeddedController.pageCount})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (!_historyStore.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _historyStore.entries;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              const Text(
                'No scanned PDFs yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Every PDF you generate in Tab 1 or Tab 2 is saved locally here for instant preview.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan a Document'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildHistoryCard(items[index]),
    );
  }

  Widget _buildHistoryCard(
    ScanHistoryEntry entry, {
    bool isLatestHighlight = false,
  }) {
    final hasCover =
        entry.coverImagePath != null &&
        File(entry.coverImagePath!).existsSync();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPreview(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 54,
                  height: 70,
                  color: Colors.teal.shade50,
                  child: hasCover
                      ? Image.file(
                          File(entry.coverImagePath!),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                        )
                      : Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Colors.teal.shade700,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLatestHighlight)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'LATEST GENERATED PDF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.pageCount} ${entry.pageCount == 1 ? 'page' : 'pages'} · '
                      '${ScanHistoryStore.formatBytes(entry.byteLength)} · '
                      '${entry.filterLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ScanHistoryStore.formatTimestamp(entry.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Preview PDF',
                onPressed: () => _openPreview(entry),
                icon: Icon(
                  Icons.visibility_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'preview') _openPreview(entry);
                  if (action == 'rename') _renameEntryDialog(entry);
                  if (action == 'delete') _historyStore.deleteEntry(entry.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'preview', child: Text('Preview PDF')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
