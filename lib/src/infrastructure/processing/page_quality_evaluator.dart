import 'package:dartcv4/dartcv.dart' as cv;

import '../../domain/crop_corners.dart';
import '../../domain/crop_models.dart';
import '../../domain/page_quality.dart';
import '../../domain/scan_filter.dart';
import 'opencv_support.dart';

/// Computes capture quality metrics (sharpness, directional motion, exposure,
/// and specular glare) on an already-decoded [colour] matrix.
Future<Map<String, double>> measureCaptureMat(
  cv.Mat colour,
  int edge,
  MatScope scope,
) async {
  final m = <String, double>{
    'width': colour.cols.toDouble(),
    'height': colour.rows.toDouble(),
  };
  final small = scope.add(await downscaleTo(colour, edge));
  final grey = scope.add(
    small.channels == 1
        ? small.clone()
        : await cv.cvtColorAsync(small, cv.COLOR_BGR2GRAY),
  );
  scope.release(small);

  final lap = scope.add(await cv.laplacianAsync(grey, cv.MatType.CV_64F));
  final (_, lapStd) = await cv.meanStdDevAsync(lap);
  m['sharpness'] = lapStd.val1 * lapStd.val1;
  scope.release(lap);

  final gx = scope.add(await cv.sobelAsync(grey, cv.MatType.CV_32F, 1, 0));
  final gy = scope.add(await cv.sobelAsync(grey, cv.MatType.CV_32F, 0, 1));
  final ax = scope.add(await cv.convertScaleAbsAsync(gx));
  final ay = scope.add(await cv.convertScaleAbsAsync(gy));
  scope.release(gx);
  scope.release(gy);
  final (mx, _) = await cv.meanStdDevAsync(ax);
  final (my, _) = await cv.meanStdDevAsync(ay);
  scope.release(ax);
  scope.release(ay);
  final hi = mx.val1 > my.val1 ? mx.val1 : my.val1;
  final lo = mx.val1 > my.val1 ? my.val1 : mx.val1;
  m['motion_ratio'] = lo <= 0.01 ? 1 : hi / lo;

  final (mean, std) = await cv.meanStdDevAsync(grey);
  m['mean'] = mean.val1;
  m['std'] = std.val1;
  final total = (grey.rows * grey.cols).toDouble();
  final dark = scope.add(
    (await cv.thresholdAsync(grey, 50, 255, cv.THRESH_BINARY_INV)).$2,
  );
  m['dark_share'] = cv.countNonZero(dark) / total;
  scope.release(dark);

  final blown = scope.add(
    (await cv.thresholdAsync(grey, 250, 255, cv.THRESH_BINARY)).$2,
  );
  m['bright_share'] = cv.countNonZero(blown) / total;
  final kernel = scope.add(
    await cv.getStructuringElementAsync(cv.MORPH_ELLIPSE, (7, 7)),
  );
  final blobs = scope.add(
    await cv.morphologyExAsync(blown, cv.MORPH_OPEN, kernel),
  );
  scope.release(blown);
  scope.release(kernel);
  m['glare_any'] = cv.countNonZero(blobs) / total;
  final cx = (grey.cols * 0.2).round();
  final cy = (grey.rows * 0.2).round();
  final centre = scope.add(
    blobs.region(cv.Rect(cx, cy, grey.cols - 2 * cx, grey.rows - 2 * cy)),
  );
  m['glare_center'] = cv.countNonZero(centre) / (centre.rows * centre.cols);
  scope.release(centre);
  scope.release(blobs);
  scope.release(grey);
  return m;
}

/// Evaluates numeric capture and output metrics against [QualityThresholds] to
/// produce advisory [PageQuality] diagnostics.
class PageQualityEvaluator {
  /// Creates a [PageQualityEvaluator].
  const PageQualityEvaluator({this.thresholds = const QualityThresholds()});

  /// Thresholds used to classify warnings and recommendations.
  final QualityThresholds thresholds;

  /// Evaluates capture sharpness, motion, glare, exposure, resolution, and frame border proximity.
  PageQuality assessCapture(
    Map<String, double> m, {
    CropCorners? corners,
    int imageWidth = 0,
    int imageHeight = 0,
    CropSource? source,
  }) {
    final t = thresholds;
    final issues = <QualityIssue>[];
    void add(QualityCheck c, QualityDecision d, String msg) =>
        issues.add(QualityIssue(check: c, decision: d, message: msg));

    final sharp = m['sharpness'];
    final motion = m['motion_ratio'] ?? 1;
    if (sharp != null && sharp < t.blurWarning) {
      if (motion >= t.motionRatio) {
        add(
          QualityCheck.motion,
          QualityDecision.warning,
          'Camera motion detected — retake recommended',
        );
      } else {
        add(
          QualityCheck.blur,
          sharp < t.blurFail ? QualityDecision.fail : QualityDecision.warning,
          'Page appears blurry — retake recommended',
        );
      }
    }

    final mean = m['mean'];
    if (mean != null) {
      if (mean < t.darkMean) {
        add(
          QualityCheck.underexposed,
          mean < t.darkMeanFail
              ? QualityDecision.fail
              : QualityDecision.warning,
          'Page is underexposed — try better lighting or flash',
        );
      } else if (mean > t.brightMean && (m['std'] ?? 99) < t.brightStd) {
        add(
          QualityCheck.overexposed,
          QualityDecision.warning,
          'Page is overexposed — faint text may be lost',
        );
      }
    }

    if ((m['glare_center'] ?? 0) > t.glareCentre) {
      add(
        QualityCheck.glare,
        QualityDecision.warning,
        'Glare detected near the center of the page',
      );
    } else if ((m['glare_any'] ?? 0) > t.glareAny) {
      add(
        QualityCheck.glare,
        QualityDecision.warning,
        'Glare detected on the page',
      );
    }

    final w = m['width'];
    final h = m['height'];
    if (w != null && h != null) {
      final short = w < h ? w : h;
      if (short < t.minShortEdgeFail) {
        add(
          QualityCheck.lowResolution,
          QualityDecision.fail,
          'Resolution is very low — move closer and retake',
        );
      } else if (short < t.minShortEdge) {
        add(
          QualityCheck.lowResolution,
          QualityDecision.warning,
          'Low resolution — fine text may look soft',
        );
      }
    }

    if (corners != null && source == CropSource.auto && imageWidth > 0) {
      for (final side in edgesTouchingFrame(corners, imageWidth, imageHeight)) {
        add(
          QualityCheck.cropIncomplete,
          QualityDecision.warning,
          '${_cap(side)} edge touches the camera border',
        );
      }
    }
    return PageQuality(issues: issues, metrics: m);
  }

  /// Evaluates output metrics after OpenCV enhancement.
  PageQuality assessOutput(Map<String, double> m, ScanFilter filter) {
    if (filter == ScanFilter.original) {
      return PageQuality(metrics: m);
    }
    final t = thresholds;
    final issues = <QualityIssue>[];
    void add(QualityCheck c, QualityDecision d, String msg) =>
        issues.add(QualityIssue(check: c, decision: d, message: msg));

    if ((m['out_decodable'] ?? 1) < 1) {
      add(
        QualityCheck.undecodable,
        QualityDecision.fail,
        'Processed page could not be decoded',
      );
      return PageQuality(issues: issues, metrics: m);
    }
    final w = m['out_width'] ?? 0;
    final h = m['out_height'] ?? 0;
    if (w < 64 || h < 64) {
      add(
        QualityCheck.invalidDimensions,
        QualityDecision.fail,
        'Processed page has invalid dimensions',
      );
      return PageQuality(issues: issues, metrics: m);
    }

    final inInk = m['in_ink'] ?? 0;
    final outInk = m['out_ink'] ?? 0;
    final inStd = m['in_std'] ?? 99;
    final outStd = m['out_std'] ?? 99;
    if (outStd < t.blankStd && inStd < t.blankStd * 2) {
      add(
        QualityCheck.blankPage,
        QualityDecision.warning,
        'Page appears blank',
      );
    } else if (inInk > 0.004 && outInk < inInk * t.inkKept) {
      add(
        QualityCheck.textLost,
        QualityDecision.warning,
        'Filter may have removed faint strokes — try Natural or Magic Color',
      );
    }

    if (filter != ScanFilter.natural &&
        filter != ScanFilter.blackAndWhite &&
        (m['colored_page'] ?? 0) < 1 &&
        (m['color_artwork'] ?? 0) < 1 &&
        (m['out_paper'] ?? 255) < t.greyPaper) {
      add(
        QualityCheck.greyBackground,
        QualityDecision.warning,
        'Background remained slightly grey',
      );
    }
    if ((m['out_black'] ?? 0) > t.crushedBlack &&
        (m['out_black'] ?? 0) > (m['in_black'] ?? 0) * 2 + 0.05) {
      add(
        QualityCheck.crushedDark,
        QualityDecision.warning,
        'Dark regions may have lost detail',
      );
    }
    if ((m['out_white'] ?? 0) > t.clippedWhite && inInk > 0.004) {
      add(
        QualityCheck.clippedForeground,
        QualityDecision.warning,
        'Faint content may have clipped to white',
      );
    }
    if ((m['correlation'] ?? 1) < t.minCorrelation) {
      add(
        QualityCheck.divergentOutput,
        QualityDecision.warning,
        'Enhanced output differs strongly from original — verify result',
      );
    }
    return PageQuality(issues: issues, metrics: m);
  }

  /// Returns frame sides (`top`, `right`, `bottom`, `left`) touched by [c].
  List<String> edgesTouchingFrame(CropCorners c, int w, int h) {
    final mx = w * thresholds.edgeMarginFraction;
    final my = h * thresholds.edgeMarginFraction;
    return [
      if (c.topLeft.y <= my && c.topRight.y <= my) 'top',
      if (c.topRight.x >= w - mx && c.bottomRight.x >= w - mx) 'right',
      if (c.bottomLeft.y >= h - my && c.bottomRight.y >= h - my) 'bottom',
      if (c.topLeft.x <= mx && c.bottomLeft.x <= mx) 'left',
    ];
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
