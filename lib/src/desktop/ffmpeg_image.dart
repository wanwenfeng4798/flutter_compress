import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../error_codes.dart';
import '../exceptions.dart';
import '../image_models.dart';
import 'ffmpeg_binaries.dart';
import 'plugin_cache.dart';

/// Image info / compress via ffmpeg (Windows / Linux).
abstract final class FfmpegImage {
  static Future<ImageMeta> info(String path) async {
    await FfmpegBinaries.ensureAvailable();
    final result = await Process.run(FfmpegBinaries.ffprobe, [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_streams',
      '-show_format',
      path,
    ]);
    if (result.exitCode != 0) {
      throw ImageCompressException(
        CompressErrorCode.imageInfoFailed,
        'ffprobe failed: ${result.stderr}',
      );
    }
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final streams = (decoded['streams'] as List?) ?? const [];
    Map<String, dynamic>? image;
    for (final s in streams) {
      final m = s as Map<String, dynamic>;
      if (m['codec_type'] == 'video') {
        image = m;
        break;
      }
    }
    image ??= streams.isNotEmpty ? streams.first as Map<String, dynamic> : null;
    if (image == null) {
      throw ImageCompressException(
        CompressErrorCode.imageInfoFailed,
        'No image stream in $path',
      );
    }
    final format = (decoded['format'] as Map?)?.cast<String, dynamic>() ?? {};
    final sizeBytes =
        int.tryParse('${format['size']}') ?? await File(path).length();
    final codec = '${image['codec_name'] ?? ''}'.toLowerCase();
    return ImageMeta(
      path: path,
      width: (image['width'] as num?)?.toInt() ?? 0,
      height: (image['height'] as num?)?.toInt() ?? 0,
      sizeBytes: sizeBytes,
      format: _mapCodec(codec, path),
    );
  }

  static Future<ImageCompressResult> compressFile({
    required String path,
    required ImageCompressConfig config,
    required String? outputDir,
    required String? outputName,
  }) async {
    await FfmpegBinaries.ensureAvailable();
    final meta = await info(path);
    final originalSize = meta.sizeBytes;
    final format = _resolveFormat(config, meta.format);
    final out = PluginCache.resolveOutput(
      outputDir: outputDir,
      outputName: outputName,
      sourcePath: path,
      ext: _extFor(format),
    );

    await _encode(
      inputPath: path,
      outputPath: out.path,
      config: config,
      format: format,
      srcW: meta.width,
      srcH: meta.height,
      keepExif: config.keepExif,
    );

    final compressedSize = await File(out.path).length();
    final dims = await _probeDims(out.path);
    final savedPct = originalSize == 0
        ? 0.0
        : (1 - compressedSize / originalSize) * 100;
    final shouldSkip =
        config.keepOriginalIfLarger &&
        (compressedSize >= originalSize || savedPct < config.minSavingsPercent);
    if (shouldSkip) {
      try {
        await File(out.path).delete();
      } catch (_) {}
      return ImageCompressResult(
        outputPath: path,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        width: meta.width,
        height: meta.height,
        format: meta.format ?? format,
        skipped: true,
      );
    }
    return ImageCompressResult(
      outputPath: out.path,
      originalSizeBytes: originalSize,
      compressedSizeBytes: compressedSize,
      width: dims.$1,
      height: dims.$2,
      format: format == 'heic' ? 'jpeg' : format,
      skipped: false,
    );
  }

  static Future<ImageBytesResult> compressBytes({
    required Uint8List source,
    required ImageCompressConfig config,
  }) async {
    await FfmpegBinaries.ensureAvailable();
    final tmpIn = File(
      '${PluginCache.cacheDir().path}${Platform.pathSeparator}'
      'in_${DateTime.now().millisecondsSinceEpoch}.img',
    );
    await tmpIn.writeAsBytes(source, flush: true);
    try {
      final meta = await info(tmpIn.path);
      final format = _resolveFormat(config, meta.format);
      final tmpOut = File(
        '${PluginCache.cacheDir().path}${Platform.pathSeparator}'
        'out_${DateTime.now().millisecondsSinceEpoch}.${_extFor(format)}',
      );
      await _encode(
        inputPath: tmpIn.path,
        outputPath: tmpOut.path,
        config: config,
        format: format,
        srcW: meta.width,
        srcH: meta.height,
        keepExif: config.keepExif,
      );
      final bytes = await tmpOut.readAsBytes();
      final dims = await _probeDims(tmpOut.path);
      try {
        await tmpOut.delete();
      } catch (_) {}

      final savedPct = source.isEmpty
          ? 0.0
          : (1 - bytes.length / source.length) * 100;
      final shouldSkip =
          config.keepOriginalIfLarger &&
          (bytes.length >= source.length ||
              savedPct < config.minSavingsPercent);
      if (shouldSkip) {
        return ImageBytesResult(
          bytes: source,
          originalSizeBytes: source.length,
          width: meta.width,
          height: meta.height,
          format: meta.format ?? format,
          skipped: true,
        );
      }
      return ImageBytesResult(
        bytes: bytes,
        originalSizeBytes: source.length,
        width: dims.$1,
        height: dims.$2,
        format: format == 'heic' ? 'jpeg' : format,
        skipped: false,
      );
    } finally {
      try {
        await tmpIn.delete();
      } catch (_) {}
    }
  }

  static Future<void> _encode({
    required String inputPath,
    required String outputPath,
    required ImageCompressConfig config,
    required String format,
    required int srcW,
    required int srcH,
    required bool keepExif,
  }) async {
    final scale = _scaleFilter(srcW, srcH, config.maxWidth, config.maxHeight);

    if (config.targetSizeKB != null &&
        !config.lossless &&
        (format == 'jpeg' || format == 'heic')) {
      await _encodeToTargetSize(
        inputPath: inputPath,
        outputPath: outputPath,
        scale: scale,
        targetBytes: config.targetSizeKB! * 1024,
        keepExif: keepExif,
      );
      return;
    }

    final args = <String>['-y', '-i', inputPath];
    args.addAll(_metadataArgs(keepExif));
    if (scale != null) args.addAll(['-vf', scale]);
    args.addAll(_codecArgs(format, config));
    args.add(outputPath);

    final result = await Process.run(FfmpegBinaries.ffmpeg, args);
    if (result.exitCode != 0) {
      throw ImageCompressException(
        CompressErrorCode.imageCompressFailed,
        'ffmpeg image encode failed: ${result.stderr}',
      );
    }
  }

  /// Copy or strip container/stream metadata (EXIF for JPEG, etc.).
  ///
  /// When [keepExif] is true we map all metadata from the first input; when
  /// false we strip it. Matches Android/iOS intent for JPEG; WebP/PNG support
  /// depends on the FFmpeg build.
  static List<String> _metadataArgs(bool keepExif) =>
      keepExif ? const ['-map_metadata', '0'] : const ['-map_metadata', '-1'];

  static List<String> _codecArgs(String format, ImageCompressConfig config) {
    switch (format) {
      case 'png':
        return ['-c:v', 'png'];
      case 'webp':
        if (config.lossless) {
          return ['-c:v', 'libwebp', '-lossless', '1'];
        }
        return ['-c:v', 'libwebp', '-quality', '${config.quality}'];
      default:
        return [
          '-c:v',
          'mjpeg',
          '-q:v',
          '${_jpegQ(config.lossless ? 100 : config.quality)}',
        ];
    }
  }

  static Future<void> _encodeToTargetSize({
    required String inputPath,
    required String outputPath,
    required String? scale,
    required int targetBytes,
    required bool keepExif,
  }) async {
    var lo = 2;
    var hi = 31;
    for (var i = 0; i < 8; i++) {
      final mid = (lo + hi) ~/ 2;
      final args = <String>['-y', '-i', inputPath];
      args.addAll(_metadataArgs(keepExif));
      if (scale != null) args.addAll(['-vf', scale]);
      args.addAll(['-c:v', 'mjpeg', '-q:v', '$mid', outputPath]);
      final result = await Process.run(FfmpegBinaries.ffmpeg, args);
      if (result.exitCode != 0) {
        throw ImageCompressException(
          CompressErrorCode.imageCompressFailed,
          'ffmpeg image encode failed: ${result.stderr}',
        );
      }
      final size = await File(outputPath).length();
      if (size > targetBytes) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
  }

  static Future<(int, int)> _probeDims(String path) async {
    try {
      final meta = await info(path);
      return (meta.width, meta.height);
    } catch (_) {
      return (0, 0);
    }
  }

  static String? _scaleFilter(int w, int h, int? maxW, int? maxH) {
    if (w <= 0 || h <= 0) return null;
    if (maxW == null && maxH == null) return null;
    var tw = w.toDouble();
    var th = h.toDouble();
    if (maxW != null && tw > maxW) {
      final s = maxW / tw;
      tw *= s;
      th *= s;
    }
    if (maxH != null && th > maxH) {
      final s = maxH / th;
      tw *= s;
      th *= s;
    }
    final rw = tw.round();
    final rh = th.round();
    if (rw == w && rh == h) return null;
    final ew = rw.isEven ? rw : rw - 1;
    final eh = rh.isEven ? rh : rh - 1;
    return 'scale=${ew < 2 ? 2 : ew}:${eh < 2 ? 2 : eh}';
  }

  static String _resolveFormat(ImageCompressConfig config, String? source) {
    if (config.format != null) {
      return switch (config.format!) {
        ImageFormat.jpeg => 'jpeg',
        ImageFormat.png => 'png',
        ImageFormat.webp => 'webp',
        ImageFormat.heic => 'heic',
      };
    }
    return source ?? 'jpeg';
  }

  static String _extFor(String format) => switch (format) {
    'png' => 'png',
    'webp' => 'webp',
    'heic' => 'jpg',
    _ => 'jpg',
  };

  static String? _mapCodec(String codec, String path) {
    if (codec.contains('mjpeg') || codec == 'jpeg') return 'jpeg';
    if (codec.contains('png')) return 'png';
    if (codec.contains('webp')) return 'webp';
    if (codec.contains('hevc') || codec.contains('heic')) return 'heic';
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'heic';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpeg';
    return codec.isEmpty ? null : codec;
  }

  static int _jpegQ(int quality) =>
      (31 - (quality.clamp(1, 100) / 100.0 * 29)).round().clamp(2, 31);
}
