import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/material.dart';

void main() {
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

class _ScannerPlaygroundPageState extends State<ScannerPlaygroundPage> {
  ScanMode _scanMode = ScanMode.multiPage;
  SinglePageBehavior _singleBehavior = SinglePageBehavior.reviewThenPdf;
  CaptureBackend _backend = CaptureBackend.auto;
  ScanFilter _defaultFilter = ScanFilter.magicColor;
  ScanQualityPreset _qualityPreset = ScanQualityPreset.balanced;
  PdfPageSize _pdfPageSize = PdfPageSize.fitToImage;

  ScannedPdfResult? _lastResult;
  late final CustomScannerController _embeddedController;

  @override
  void initState() {
    super.initState();
    _embeddedController = CustomScannerController(config: _buildConfig());
  }

  @override
  void dispose() {
    _embeddedController.dispose();
    super.dispose();
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
      pageSize: _pdfPageSize,
      marginsPt: _pdfPageSize.isFitToImage
          ? EdgeInsets.zero
          : const EdgeInsets.all(20),
      metadata: const PdfDocumentMetadata(title: 'Demo Scan'),
    ),
  );

  Future<void> _launchModalScanner() async {
    final result = await CustomPdfScanner.scan(context, config: _buildConfig());
    if (result != null && mounted) {
      setState(() => _lastResult = result);
    }
  }

  Future<void> _embeddedScan(ScanMode mode) async {
    _embeddedController.updateConfig(_buildConfig());
    if (_embeddedController.shouldUseNativeMlKit()) {
      await _embeddedController.captureAndProcessWithMlKit(modeOverride: mode);
    } else {
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
    _embeddedController.updateConfig(_buildConfig());
    final res = await _embeddedController.generatePdf();
    if (mounted) {
      setState(() => _lastResult = res);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${res.pageCount}-page PDF: ${res.pdfPath}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('custom_pdf_scanner SDK'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '1. Modal Launcher'),
              Tab(text: '2. Embedded Reorderable List'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildLauncherTab(), _buildEmbeddedTab()]),
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
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _launchModalScanner,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Launch CustomPdfScanner.scan()'),
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generated PDF (${_lastResult!.pageCount} pages)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text('Path: ${_lastResult!.pdfPath}'),
                  Text('Size: ${_lastResult!.byteLength} bytes'),
                  if (_lastResult!.sha256 != null)
                    Text('SHA-256: ${_lastResult!.sha256}'),
                ],
              ),
            ),
          ),
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
                    child: FilledButton(
                      onPressed:
                          _embeddedController.isEmpty ||
                              _embeddedController.isBusy
                          ? null
                          : _embeddedGeneratePdf,
                      child: Text(
                        'Save PDF (${_embeddedController.pageCount})',
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
}
