import 'dart:io';
import 'dart:typed_data';

/// Oriented pixel dimensions, raw dimensions, color components, and EXIF
/// orientation tag read directly from a JPEG header without decoding pixels.
typedef JpegHeaderInfo = ({
  int width,
  int height,
  int rawWidth,
  int rawHeight,
  int components,
  int orientation,
});

/// Reads oriented `(width, height)` from a JPEG file header, or returns `null`
/// if [path] is not a JPEG.
Future<(int width, int height)?> orientedJpegSize(String path) async {
  final info = await orientedJpegInfo(path);
  return info == null ? null : (info.width, info.height);
}

/// Reads [JpegHeaderInfo] from the first 256 KB of [path].
Future<JpegHeaderInfo?> orientedJpegInfo(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final raf = await file.open();
  try {
    final head = await raf.read(256 * 1024);
    return parseOrientedJpegInfo(head);
  } finally {
    await raf.close();
  }
}

/// Parses [JpegHeaderInfo] from raw JPEG header bytes [b].
JpegHeaderInfo? parseOrientedJpegInfo(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var orientation = 1;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) break;
    final length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;
    final start = i + 4;
    if (marker == 0xE1 &&
        start + 6 <= b.length &&
        String.fromCharCodes(b.sublist(start, start + 4)) == 'Exif') {
      orientation = _exifOrientation(b, start + 6) ?? orientation;
    }
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof && start + 6 <= b.length) {
      final rawH = (b[start + 1] << 8) | b[start + 2];
      final rawW = (b[start + 3] << 8) | b[start + 4];
      final components = b[start + 5];
      final swapped = orientation >= 5 && orientation <= 8;
      return (
        width: swapped ? rawH : rawW,
        height: swapped ? rawW : rawH,
        rawWidth: rawW,
        rawHeight: rawH,
        components: components,
        orientation: orientation,
      );
    }
    i = start + length - 2;
  }
  return null;
}

int? _exifOrientation(Uint8List b, int tiff) {
  if (tiff + 8 > b.length) return null;
  final little = b[tiff] == 0x49;
  int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => little
      ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
      : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > b.length) return null;
  final count = u16(ifd);
  for (var e = 0; e < count; e++) {
    final entry = ifd + 2 + e * 12;
    if (entry + 12 > b.length) return null;
    if (u16(entry) == 0x0112) return u16(entry + 8);
  }
  return null;
}
