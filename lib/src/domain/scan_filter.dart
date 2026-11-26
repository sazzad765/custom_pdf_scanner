/// Enhancement filter applied to a cropped document page.
enum ScanFilter {
  /// Uses the perspective-cropped page as-is at the configured resolution limit
  /// without tonal adjustments.
  natural('natural', 'Natural'),

  /// Removes uneven lighting and shadows, whitens paper, preserves color inks
  /// (stamps, signatures, artwork), and sharpens text.
  magicColor('magic_color', 'Magic Color'),

  /// Applies illumination flattening, shadow cleanup, and paper whitening in
  /// 8-bit grayscale.
  grayscale('grayscale', 'Grayscale'),

  /// Applies Sauvola adaptive local thresholding and encodes losslessly as an
  /// 8-bit PNG (and `/FlateDecode` stream in PDF) so text edges never show JPEG
  /// ringing artifacts.
  blackAndWhite('black_white', 'Black & White'),

  /// Bypasses OpenCV enhancement entirely and uses the perspective-cropped
  /// source JPEG directly without re-encoding.
  original('original', 'Original');

  const ScanFilter(this.id, this.defaultLabel);

  /// Stable string identifier suitable for serialization.
  final String id;

  /// Default English UI label (can be overridden via `ScannerStrings`).
  final String defaultLabel;

  /// File extension produced by this filter (`png` for lossless [blackAndWhite],
  /// `jpg` for all other filters).
  String get fileExtension => this == blackAndWhite ? 'png' : 'jpg';

  /// Looks up a [ScanFilter] by its [id], defaulting to [magicColor].
  static ScanFilter fromId(String? value) => ScanFilter.values.firstWhere(
    (f) => f.id == value,
    orElse: () => ScanFilter.magicColor,
  );
}
