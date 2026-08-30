import 'dart:typed_data';

// Image-compression models — deliberately separate from the video models so the
// two APIs never blur together.

/// Output container/codec for image compression.
enum ImageFormat {
  /// Lossy, universal. Quality-controlled.
  jpeg,

  /// Lossless (quality is ignored; target-size is met by downscaling).
  png,

  /// Lossy, ~30% smaller than JPEG at similar quality. Web: Chrome/Firefox.
  webp,

  /// Lossy, best ratio. iOS native; Android needs a HEIC encoder (else the
  /// engine falls back to JPEG). Not available on Web.
  heic,
}

/// Image compression request.
///
/// Priority: [lossless] > [targetSizeKB] (iterative, precise) > [quality].
class ImageCompressConfig {
  const ImageCompressConfig({
    this.format,
    this.quality = 85,
    this.targetSizeKB,
    this.maxWidth,
    this.maxHeight,
    this.keepExif = false,
    this.lossless = false,
    this.keepOriginalIfLarger = true,
    this.minSavingsPercent = 0,
  })  : assert(quality >= 1 && quality <= 100, 'quality must be 1–100'),
        assert(targetSizeKB == null || targetSizeKB > 0,
            'targetSizeKB must be > 0'),
        assert(maxWidth == null || maxWidth > 0, 'maxWidth must be > 0'),
        assert(maxHeight == null || maxHeight > 0, 'maxHeight must be > 0'),
        assert(minSavingsPercent >= 0 && minSavingsPercent < 100,
            'minSavingsPercent must be 0–99');

  /// Sized for upload as an avatar or thumbnail: 512px cap, JPEG, modest
  /// quality. Format is forced because a 4 MB PNG avatar is the common mistake.
  const ImageCompressConfig.forAvatar({
    this.maxWidth = 512,
    this.maxHeight = 512,
  })  : format = ImageFormat.jpeg,
        quality = 80,
        targetSizeKB = null,
        keepExif = false,
        lossless = false,
        keepOriginalIfLarger = true,
        minSavingsPercent = 0;

  /// A photo destined for a social post: 2048px cap, source format kept, EXIF
  /// dropped so location data doesn't leak with the upload.
  const ImageCompressConfig.forSocialMedia({
    this.maxWidth = 2048,
    this.maxHeight = 2048,
    this.targetSizeKB = 500,
  })  : format = null,
        quality = 85,
        keepExif = false,
        lossless = false,
        keepOriginalIfLarger = true,
        minSavingsPercent = 0;

  /// Output format. When `null` (the default), the **source's format is kept**
  /// (a PNG stays PNG, a JPEG stays JPEG); set it only to convert to a specific
  /// format. HEIC without a platform encoder falls back to JPEG; the real
  /// output format is reported on [ImageCompressResult.format].
  final ImageFormat? format;

  /// 1–100 quality, used when [targetSizeKB] is null (ignored for PNG).
  final int quality;

  /// Desired output size in KB. The native engines iterate (binary-search the
  /// quality, then downscale if needed) to land at or just under this — images
  /// encode in milliseconds, so this is accurate, unlike single-pass video.
  final int? targetSizeKB;

  /// Cap dimensions; aspect ratio is kept and the image is only scaled down.
  final int? maxWidth;
  final int? maxHeight;

  /// Keep EXIF metadata (orientation, GPS, …). Default strips it.
  final bool keepExif;

  /// Encode losslessly (pixel-for-pixel). When true, [quality] and
  /// [targetSizeKB] are ignored — you can't lossless-encode to an arbitrary
  /// size. The output **format is preserved**: PNG is truly lossless;
  /// [ImageFormat.webp] uses its lossless mode where the platform supports it;
  /// [ImageFormat.jpeg] has no lossless mode, so it stays JPEG encoded at
  /// maximum quality (100). ([ImageFormat.heic] still falls back to JPEG on
  /// platforms without a HEIC encoder.) [maxWidth] / [maxHeight] still apply if
  /// set — "lossless" refers to the encode, not the resize.
  final bool lossless;

  /// If the compressed output would be **larger** than the source (common when
  /// re-encoding an already-compressed JPEG, or with lossless), keep the
  /// original untouched and mark the result [ImageCompressResult.skipped].
  /// Defaults to `true`. [ImageCompressResult.outputPath] then points at the
  /// source, with its original size/format/dimensions.
  final bool keepOriginalIfLarger;

  /// How much the output must actually save before it is worth using, in
  /// percent of the source size. Requires [keepOriginalIfLarger].
  ///
  /// `0` (the default) keeps the original only when the output would be *larger*
  /// or equal. Raise it to reject marginal wins: at `5`, an output that shaves
  /// only 3% comes back as [ImageCompressResult.skipped] with the source path,
  /// because swapping files — and losing whatever metadata the re-encode drops —
  /// isn't worth 3%.
  final int minSavingsPercent;

  Map<String, dynamic> toMap() => {
        'format': format?.name,
        'quality': quality,
        'targetSizeKB': targetSizeKB,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'keepExif': keepExif,
        'lossless': lossless,
        'keepOriginalIfLarger': keepOriginalIfLarger,
        'minSavingsPercent': minSavingsPercent,
      };
}

/// Metadata about a source image. (Named `ImageMeta` to avoid clashing with
/// Flutter's `ImageInfo`.)
class ImageMeta {
  const ImageMeta({
    required this.path,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.format,
  });

  final String path;
  final int width;
  final int height;
  final int sizeBytes;
  final String? format;

  factory ImageMeta.fromMap(Map<dynamic, dynamic> m) => ImageMeta(
        path: m['path'] as String,
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        sizeBytes: (m['sizeBytes'] as num).toInt(),
        format: m['format'] as String?,
      );
}

/// Result of a completed image compression.
class ImageCompressResult {
  const ImageCompressResult({
    required this.outputPath,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.width,
    required this.height,
    required this.format,
    this.skipped = false,
  });

  final String outputPath;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final int width;
  final int height;

  /// The format actually written ("jpeg"/"png"/"webp"/"heic") — may differ
  /// from the request if a fallback occurred.
  final String format;

  /// True when compression was skipped because it would not have reduced size
  /// (see [ImageCompressConfig.keepOriginalIfLarger]); [outputPath] then points
  /// at the untouched source.
  final bool skipped;

  double get compressionRatio =>
      originalSizeBytes == 0 ? 1 : compressedSizeBytes / originalSizeBytes;

  double get savedPercent => (1 - compressionRatio) * 100;

  factory ImageCompressResult.fromMap(Map<dynamic, dynamic> m) =>
      ImageCompressResult(
        outputPath: m['outputPath'] as String,
        originalSizeBytes: (m['originalSizeBytes'] as num).toInt(),
        compressedSizeBytes: (m['compressedSizeBytes'] as num).toInt(),
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        format: m['format'] as String,
        skipped: m['skipped'] as bool? ?? false,
      );
}

/// Result of an in-memory image compression (see
/// `FlutterCompress.compressImageBytes`). Mirrors [ImageCompressResult] but
/// carries the encoded bytes instead of a path — nothing is written to disk.
class ImageBytesResult {
  const ImageBytesResult({
    required this.bytes,
    required this.originalSizeBytes,
    required this.width,
    required this.height,
    required this.format,
    this.skipped = false,
  });

  /// The encoded image. When [skipped] is true these are the **source** bytes,
  /// returned unchanged.
  final Uint8List bytes;

  final int originalSizeBytes;
  final int width;
  final int height;

  /// The format actually written ("jpeg"/"png"/"webp"/"heic") — may differ from
  /// the request when a platform lacks that encoder.
  final String format;

  /// True when re-encoding would not have helped, so the source was returned
  /// untouched (see [ImageCompressConfig.keepOriginalIfLarger] and
  /// [ImageCompressConfig.minSavingsPercent]).
  final bool skipped;

  int get compressedSizeBytes => bytes.length;

  double get compressionRatio =>
      originalSizeBytes == 0 ? 1 : compressedSizeBytes / originalSizeBytes;

  double get savedPercent => (1 - compressionRatio) * 100;

  factory ImageBytesResult.fromMap(Map<dynamic, dynamic> m) => ImageBytesResult(
        bytes: m['bytes'] as Uint8List,
        originalSizeBytes: (m['originalSizeBytes'] as num).toInt(),
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        format: m['format'] as String,
        skipped: m['skipped'] == true,
      );
}
