import 'dart:convert';
import 'dart:io';

import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/synthetic_page_helper.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_builder_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'streams mixed Color JPEG (/DCTDecode), Grayscale JPEG, and B&W PNG (/FlateDecode) into valid PDF 1.4',
    () async {
      final croppedPath = await SyntheticPageHelper.writeCroppedJpeg(
        tempDir,
        name: 'src.jpg',
      );
      const processor = OpenCvPageProcessor(
        config: ProcessingConfig(useIsolate: false),
      );

      final magicPath = p.join(tempDir.path, 'p1_magic.jpg');
      final grayPath = p.join(tempDir.path, 'p2_gray.jpg');
      final bwPath = p.join(tempDir.path, 'p3_bw.png');

      await processor.processPage(
        croppedPath: croppedPath,
        filter: ScanFilter.magicColor,
        outputPath: magicPath,
      );
      await processor.processPage(
        croppedPath: croppedPath,
        filter: ScanFilter.grayscale,
        outputPath: grayPath,
      );
      await processor.processPage(
        croppedPath: croppedPath,
        filter: ScanFilter.blackAndWhite,
        outputPath: bwPath,
      );

      final pdfOut = p.join(tempDir.path, 'mixed_output.pdf');
      const builder = LocalPdfBuilder(
        config: PdfConfig(
          pageSize: PdfPageSize.a4,
          marginsPt: EdgeInsets.all(18),
          metadata: PdfDocumentMetadata(
            title: 'BGDCL বাংলা Test Document',
            author: 'UnitTest',
          ),
          useIsolate: false,
        ),
      );

      final progressEvents = <PdfGenerationProgress>[];
      final res = await builder.buildFromFiles(
        pages: [
          PdfPageInput(imagePath: magicPath),
          PdfPageInput(imagePath: grayPath, extraRotationQuarterTurns: 1),
          PdfPageInput(imagePath: bwPath),
        ],
        outputFilePath: pdfOut,
        onProgress: progressEvents.add,
      );

      expect(res.pageCount, 3);
      expect(progressEvents.length, 3);
      expect(progressEvents.last.completedPages, 3);
      expect(res.sha256, isNotNull);
      expect(res.sha256!.length, 64);

      final bytes = await File(pdfOut).readAsBytes();
      expect(bytes.length, res.byteLength);
      final rawText = latin1.decode(bytes, allowInvalid: true);

      expect(rawText.startsWith('%PDF-1.4\n'), isTrue);
      expect(rawText, contains('/Count 3'));
      expect(rawText, contains('/Filter /DCTDecode'));
      expect(rawText, contains('/Filter /FlateDecode'));
      expect(rawText, contains('/ColorSpace /DeviceRGB'));
      expect(rawText, contains('/ColorSpace /DeviceGray'));
      // Unicode UTF-16BE BOM hex string for non-ASCII title.
      expect(rawText, contains('/Title <FEFF'));
      expect(rawText.trimRight().endsWith('%%EOF'), isTrue);
    },
  );
}
