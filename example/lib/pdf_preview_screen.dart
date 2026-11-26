import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import 'scan_history_store.dart';

/// Interactive local PDF viewer screen with page indicator, document metadata
/// inspector, Save-to-Device export, and delete support.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    required this.entry,
    required this.historyStore,
    super.key,
  });

  final ScanHistoryEntry entry;
  final ScanHistoryStore historyStore;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  PDFViewController? _pdfController;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;
  bool _savingCopy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _totalPages = widget.entry.pageCount;
  }

  Future<void> _exportCopyToDevice() async {
    if (_savingCopy) return;
    setState(() => _savingCopy = true);
    try {
      final bytes = await File(widget.entry.pdfPath).readAsBytes();
      final safeName = widget.entry.title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final fileName =
          '${safeName.isEmpty ? 'scanned_document' : safeName}.pdf';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF to Device',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF saved successfully.')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingCopy = false);
    }
  }

  void _showMetadataSheet() {
    final item = widget.entry;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _infoRow('Pages', '${item.pageCount}'),
              _infoRow(
                'File Size',
                ScanHistoryStore.formatBytes(item.byteLength),
              ),
              _infoRow('Mode', item.scanModeLabel),
              _infoRow('Filter', item.filterLabel),
              _infoRow('Page Size', item.pageSizeLabel),
              _infoRow(
                'Created',
                ScanHistoryStore.formatTimestamp(item.createdAt),
              ),
              _infoRow('Local Path', item.pdfPath),
              if (item.sha256 != null) _infoRow('SHA-256', item.sha256!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete PDF?'),
        content: Text('Remove "${widget.entry.title}" from history and disk?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.historyStore.deleteEntry(widget.entry.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileExists = File(widget.entry.pdfPath).existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF1E293B),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.entry.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              '${widget.entry.pageCount} pages · ${ScanHistoryStore.formatBytes(widget.entry.byteLength)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Save PDF to Downloads / Files',
            onPressed: !fileExists || _savingCopy ? null : _exportCopyToDevice,
            icon: _savingCopy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Document Details',
            onPressed: _showMetadataSheet,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: 'Delete PDF',
            onPressed: _confirmDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade400,
            ),
          ),
        ],
      ),
      body: !fileExists
          ? const Center(
              child: Text(
                'PDF file was not found on disk.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Stack(
              children: [
                PDFView(
                  filePath: widget.entry.pdfPath,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: false,
                  fitEachPage: true,
                  onRender: (pages) {
                    if (mounted) {
                      setState(() {
                        _totalPages = pages ?? widget.entry.pageCount;
                        _isReady = true;
                      });
                    }
                  },
                  onViewCreated: (controller) => _pdfController = controller,
                  onPageChanged: (page, total) {
                    if (mounted) {
                      setState(() {
                        _currentPage = page ?? 0;
                        if (total != null && total > 0) _totalPages = total;
                      });
                    }
                  },
                  onError: (error) {
                    if (mounted) {
                      setState(() => _errorMessage = '$error');
                    }
                  },
                ),
                if (!_isReady && _errorMessage == null)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not render PDF: $_errorMessage',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (_isReady && _totalPages > 0)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_totalPages > 1)
                              InkWell(
                                onTap: _currentPage > 0
                                    ? () => _pdfController?.setPage(
                                        _currentPage - 1,
                                      )
                                    : null,
                                child: Icon(
                                  Icons.chevron_left_rounded,
                                  color: _currentPage > 0
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 20,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                'Page ${_currentPage + 1} of $_totalPages',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_totalPages > 1)
                              InkWell(
                                onTap: _currentPage + 1 < _totalPages
                                    ? () => _pdfController?.setPage(
                                        _currentPage + 1,
                                      )
                                    : null,
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: _currentPage + 1 < _totalPages
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
