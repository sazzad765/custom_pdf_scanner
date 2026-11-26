import 'dart:io';

import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/synthetic_page_helper.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scanner_ctrl_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'multi-page batch OpenCV processing -> reorder -> add more -> batch filter -> local PDF',
    () async {
      final p1 = await SyntheticPageHelper.writePerspectiveDeskPhoto(
        tempDir,
        name: 'desk1.jpg',
        markerBand: 1,
      );
      final p2 = await SyntheticPageHelper.writePerspectiveDeskPhoto(
        tempDir,
        name: 'desk2.jpg',
        markerBand: 2,
      );
      final p3 = await SyntheticPageHelper.writeCroppedJpeg(
        tempDir,
        name: 'extra3.jpg',
        markerBand: 3,
      );

      final controller = CustomScannerController(
        config: CustomScannerConfig(
          workingDirectoryPath: tempDir.path,
          processing: const ProcessingConfig(
            defaultFilter: ScanFilter.magicColor,
            useIsolate: false,
          ),
          pdf: PdfConfig(
            outputDirectoryPath: tempDir.path,
            deleteTempFilesAfterExport: false,
            useIsolate: false,
          ),
        ),
      );

      final batchUpdates = <BatchProcessingProgress>[];
      controller.addListener(() {
        if (controller.batchProgress != null) {
          batchUpdates.add(controller.batchProgress!);
        }
      });

      // 1. Initial multi-page batch (2 perspective photos auto-cropped & enhanced).
      final firstBatch = await controller.addImageFiles([p1, p2]);
      expect(firstBatch.length, 2);
      expect(controller.pageCount, 2);
      expect(firstBatch[0].cropSource, CropSource.auto);
      expect(firstBatch[0].pageNumber, 1);
      expect(firstBatch[1].pageNumber, 2);
      expect(batchUpdates, isNotEmpty);

      final firstId = controller.pages[0].id;
      final secondId = controller.pages[1].id;

      // 2. "+ Add More" appends a 3rd page into the local list!
      await controller.addImageFiles([p3], preCropped: true);
      expect(controller.pageCount, 3);
      final thirdId = controller.pages[2].id;

      // 3. Reorder: move page 3 to the front (index 2 -> index 0).
      controller.movePage(2, 0);
      expect(controller.pages.map((p) => p.id).toList(), [
        thirdId,
        firstId,
        secondId,
      ]);
      expect(controller.pages.map((p) => p.pageNumber).toList(), [1, 2, 3]);

      // 4. Rotate page 1 and apply Black & White filter to all pages in batch.
      await controller.rotatePage(thirdId);
      expect(controller.pageById(thirdId)!.rotationQuarterTurns, 1);

      await controller.applyFilterToAll(ScanFilter.blackAndWhite);
      expect(
        controller.pages.every((p) => p.filter == ScanFilter.blackAndWhite),
        isTrue,
      );
      expect(
        controller.pages.every((p) => p.exportPath.endsWith('.png')),
        isTrue,
      );

      // 5. Generate local PDF and verify output.
      final pdfResult = await controller.generatePdf(
        outputFilePath: p.join(tempDir.path, 'final_reordered.pdf'),
      );
      expect(pdfResult.pageCount, 3);
      expect(await pdfResult.pdfFile.exists(), isTrue);
      expect(pdfResult.byteLength, greaterThan(1000));
      expect(pdfResult.pages.first.id, thirdId);

      await controller.disposeWorkspaceAndController(deleteTempFiles: true);
    },
  );

  test(
    'headless CustomPdfScanner.processFilesToPdf processes 1 page cleanly',
    () async {
      final singlePhoto = await SyntheticPageHelper.writePerspectiveDeskPhoto(
        tempDir,
        name: 'single.jpg',
      );
      final outPdf = p.join(tempDir.path, 'single_out.pdf');

      final result = await CustomPdfScanner.processFilesToPdf(
        imagePaths: [singlePhoto],
        outputFilePath: outPdf,
        config: CustomScannerConfig.singlePage(
          processing: const ProcessingConfig(useIsolate: false),
          pdf: const PdfConfig(
            deleteTempFilesAfterExport: true,
            useIsolate: false,
          ),
        ),
      );

      expect(result.pageCount, 1);
      expect(await File(outPdf).exists(), isTrue);
    },
  );
}
