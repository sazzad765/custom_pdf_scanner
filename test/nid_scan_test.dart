import 'dart:convert';
import 'dart:io';

import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/synthetic_page_helper.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nid_scan_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'ScanMode.nidCard composes Front and Back onto 1 single A4 PDF page with two XObjects',
    () async {
      final frontImg = await SyntheticPageHelper.writeCroppedJpeg(
        tempDir,
        name: 'nid_front.jpg',
        markerBand: 1,
      );
      final backImg = await SyntheticPageHelper.writeCroppedJpeg(
        tempDir,
        name: 'nid_back.jpg',
        markerBand: 2,
      );

      final controller = CustomScannerController(
        config: CustomScannerConfig.nidCard(
          nid: const NidScanConfig(
            sides: NidScanSides.frontAndBack,
            pdfLayout: NidPdfLayout.topAndBottomSinglePage,
            cardPrintSize: NidCardPrintSize.actualIsoId1,
          ),
          processing: const ProcessingConfig(useIsolate: false),
          pdf: PdfConfig(outputDirectoryPath: tempDir.path, useIsolate: false),
        ),
      );

      await controller.addImageFiles([frontImg, backImg], preCropped: true);
      expect(controller.pageCount, 2);
      expect(controller.remainingPageSlots, 0);

      final originalFrontId = controller.pages[0].id;
      final originalBackId = controller.pages[1].id;
      controller.swapFrontAndBack();
      expect(controller.pages[0].id, originalBackId);
      expect(controller.pages[1].id, originalFrontId);
      expect(controller.pages[0].pageNumber, 1);
      expect(controller.pages[1].pageNumber, 2);

      // Export 1-page composite PDF (Top & Bottom, ISO ID-1 size).
      final singlePagePdf = await controller.generatePdf(
        outputFilePath: p.join(tempDir.path, 'nid_1page.pdf'),
      );
      expect(singlePagePdf.pageCount, 1);
      expect(singlePagePdf.pages.length, 2);

      final rawSingle = latin1.decode(
        await singlePagePdf.pdfFile.readAsBytes(),
        allowInvalid: true,
      );
      expect(rawSingle, contains('/Count 1'));
      expect(rawSingle, contains('/Im0 Do'));
      expect(rawSingle, contains('/Im1 Do'));
      expect(rawSingle, contains('/MediaBox [0 0 595.28 841.89]'));

      // Export 2-page separate NID PDF via overrideNidConfig.
      final separatePdf = await controller.generatePdf(
        outputFilePath: p.join(tempDir.path, 'nid_2pages.pdf'),
        overrideNidConfig: const NidScanConfig(
          pdfLayout: NidPdfLayout.separatePages,
        ),
      );
      expect(separatePdf.pageCount, 2);
      final rawSeparate = latin1.decode(
        await separatePdf.pdfFile.readAsBytes(),
        allowInvalid: true,
      );
      expect(rawSeparate, contains('/Count 2'));

      await controller.disposeWorkspaceAndController(deleteTempFiles: true);
    },
  );
}
