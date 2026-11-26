import 'package:custom_pdf_scanner/custom_pdf_scanner.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CropCorners geometry', () {
    test('orders arbitrary rotated corners clockwise from top-left', () {
      final unordered = [
        const PagePoint(500, 700),
        const PagePoint(100, 80),
        const PagePoint(90, 690),
        const PagePoint(510, 95),
      ];
      final ordered = CropCorners.ordered(unordered);
      expect(ordered.topLeft, const PagePoint(100, 80));
      expect(ordered.topRight, const PagePoint(510, 95));
      expect(ordered.bottomRight, const PagePoint(500, 700));
      expect(ordered.bottomLeft, const PagePoint(90, 690));
      expect(ordered.isConvex, isTrue);
      expect(ordered.minAngle, greaterThan(75));
    });

    test('detects non-convex crossed bow-tie quads', () {
      const crossed = CropCorners(
        topLeft: PagePoint(0, 0),
        topRight: PagePoint(100, 100),
        bottomRight: PagePoint(100, 0),
        bottomLeft: PagePoint(0, 100),
      );
      expect(crossed.isConvex, isFalse);
    });
  });

  group('CustomScannerConfig customization', () {
    test('singlePage and multiPage factory presets set expected limits', () {
      final single = CustomScannerConfig.singlePage(
        behavior: SinglePageBehavior.immediatePdf,
      );
      expect(single.capture.scanMode, ScanMode.singlePage);
      expect(
        single.capture.singlePageBehavior,
        SinglePageBehavior.immediatePdf,
      );
      expect(single.capture.maxPages, 1);

      final multi = CustomScannerConfig.multiPage(
        maxPages: 150,
        processing: ProcessingConfig.fromPreset(
          ScanQualityPreset.high,
          defaultFilter: ScanFilter.blackAndWhite,
        ),
        pdf: const PdfConfig(
          pageSize: PdfPageSize.a4,
          marginsPt: EdgeInsets.all(24),
        ),
      );
      expect(multi.capture.scanMode, ScanMode.multiPage);
      expect(multi.capture.maxPages, 150);
      expect(multi.processing.defaultFilter, ScanFilter.blackAndWhite);
      expect(multi.processing.maxLongEdge, 0);
      expect(multi.pdf.pageSize, PdfPageSize.a4);
      expect(multi.pdf.marginsPt, const EdgeInsets.all(24));
    });
  });
}
