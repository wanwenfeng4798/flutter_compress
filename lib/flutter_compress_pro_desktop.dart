import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'flutter_compress_pro_platform_interface.dart';
import 'src/desktop/ffmpeg_binaries.dart';
import 'src/desktop/ffmpeg_image.dart';
import 'src/desktop/ffmpeg_video.dart';
import 'src/desktop/plugin_cache.dart';
import 'src/error_codes.dart';
import 'src/exceptions.dart';
import 'src/image_models.dart';
import 'src/models.dart';
import 'src/size_math.dart';

/// Windows / Linux backend that shells out to system `ffmpeg` / `ffprobe`.
///
/// macOS, Android, iOS and Web use other engines and do **not** go through this
/// class. Register via `dartPluginClass` in pubspec.
class FlutterCompressDesktop extends FlutterCompressPlatform {
  /// Called by Flutter's plugin registrant for linux/windows.
  static void registerWith() {
    FlutterCompressPlatform.instance = FlutterCompressDesktop();
  }

  final _progressController = StreamController<CompressionProgress>.broadcast();

  Process? _activeProcess;
  String? _activeId;
  String? _preCancelledId;

  @override
  Stream<CompressionProgress> get progressStream => _progressController.stream;

  @override
  Future<VideoInfo> getVideoInfo(String path) async {
    try {
      return await FfmpegVideo.probe(path);
    } on CompressException {
      rethrow;
    } catch (e) {
      throw VideoCompressException(CompressErrorCode.infoFailed, '$e');
    }
  }

  @override
  Future<CompressionEstimate> estimate(
    String path,
    VideoCompressConfig config,
  ) async {
    try {
      final info = await FfmpegVideo.probe(path);
      final durationMs = _clampDuration(info.durationMs, config);
      final dims = SizeMath.targetDimensions(info.width, info.height, config);
      final videoBps = SizeMath.videoBitrateBps(
        config: config,
        durationMs: durationMs,
        sourceBitrateKbps: info.bitrateKbps,
        targetHeight: dims.$2,
      );
      final audioBps = config.removeAudio
          ? 0
          : (config.audioBitrateKbps ?? 128) * 1000;
      final totalBits = (videoBps + audioBps) * durationMs ~/ 1000;
      return CompressionEstimate(
        estimatedSizeBytes: totalBits ~/ 8,
        estimatedBitrateKbps: (videoBps + audioBps) ~/ 1000,
        targetWidth: dims.$1,
        targetHeight: dims.$2,
      );
    } on CompressException {
      rethrow;
    } catch (e) {
      throw VideoCompressException(CompressErrorCode.estimateFailed, '$e');
    }
  }

  @override
  Future<VideoCompressResult> compress(
    String id,
    String path,
    VideoCompressConfig config,
    String? outputDir,
    String? outputName,
  ) async {
    if (_preCancelledId == id) {
      _preCancelledId = null;
      throw VideoCompressCancelledException();
    }
    try {
      await FfmpegBinaries.ensureAvailable();
      final info = await FfmpegVideo.probe(path);
      final originalSize = await File(path).length();
      final durationMs = _clampDuration(info.durationMs, config);
      final dims = SizeMath.targetDimensions(info.width, info.height, config);
      final videoBps = SizeMath.videoBitrateBps(
        config: config,
        durationMs: durationMs,
        sourceBitrateKbps: info.bitrateKbps,
        targetHeight: dims.$2,
      );
      final outFile = PluginCache.resolveOutput(
        outputDir: outputDir,
        outputName: outputName,
        sourcePath: path,
        ext: 'mp4',
      );

      final result = await FfmpegVideo.compress(
        id: id,
        inputPath: path,
        outputPath: outFile.path,
        config: config,
        info: info,
        targetWidth: dims.$1,
        targetHeight: dims.$2,
        videoBitrateBps: videoBps,
        durationMs: durationMs,
        onProgress: (progress) {
          if (!_progressController.isClosed) {
            _progressController.add(
              CompressionProgress(id: id, progress: progress),
            );
          }
        },
        onProcess: (proc) {
          _activeProcess = proc;
          _activeId = id;
        },
        isCancelled: () => _preCancelledId == id,
      );

      _activeProcess = null;
      _activeId = null;

      if (result.cancelled) {
        throw VideoCompressCancelledException();
      }

      final usedCodec = result.usedCodec;
      final compressedSize = await File(outFile.path).length();
      final minSave = config.minSavingsPercent;
      final savedPct = originalSize == 0
          ? 0.0
          : (1 - compressedSize / originalSize) * 100;
      final shouldSkip =
          config.keepOriginalIfLarger &&
          (compressedSize >= originalSize || savedPct < minSave);
      if (shouldSkip) {
        try {
          await File(outFile.path).delete();
        } catch (_) {}
        return VideoCompressResult(
          id: id,
          outputPath: path,
          originalSizeBytes: originalSize,
          compressedSizeBytes: originalSize,
          width: info.width,
          height: info.height,
          durationMs: info.durationMs,
          codec: info.codec ?? usedCodec,
          skipped: true,
          frameRate: info.frameRate,
          hasAudio: !config.removeAudio,
        );
      }

      return VideoCompressResult(
        id: id,
        outputPath: outFile.path,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        width: dims.$1,
        height: dims.$2,
        durationMs: durationMs,
        codec: usedCodec,
        skipped: false,
        frameRate: config.frameRate ?? info.frameRate,
        hasAudio: !config.removeAudio,
      );
    } on CompressException {
      rethrow;
    } catch (e) {
      throw VideoCompressException(CompressErrorCode.compressFailed, '$e');
    } finally {
      _activeProcess = null;
      if (_activeId == id) _activeId = null;
    }
  }

  @override
  Future<void> cancel(String? id) async {
    if (id != null && (_activeId == null || _activeId != id)) {
      _preCancelledId = id;
    }
    final proc = _activeProcess;
    if (proc != null && (id == null || id == _activeId)) {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  @override
  Future<bool> isCompressing() async => _activeProcess != null;

  @override
  Future<String> getThumbnail(
    String path, {
    required int positionMs,
    required int quality,
    int? maxWidth,
  }) async {
    try {
      return await FfmpegVideo.thumbnail(
        path: path,
        positionMs: positionMs,
        quality: quality,
        maxWidth: maxWidth,
        outDir: PluginCache.cacheDir(),
      );
    } on CompressException {
      rethrow;
    } catch (e) {
      throw VideoCompressException(CompressErrorCode.thumbnailFailed, '$e');
    }
  }

  @override
  Future<void> clearCache() async {
    await PluginCache.clear();
  }

  @override
  Future<String> saveToDownloads(String path, String? fileName) async {
    try {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      final downloads = Directory('$home${Platform.pathSeparator}Downloads');
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      final name = fileName ?? path.split(RegExp(r'[/\\]')).last;
      final dest = File('${downloads.path}${Platform.pathSeparator}$name');
      if (await dest.exists()) await dest.delete();
      await File(path).copy(dest.path);
      return dest.path;
    } catch (e) {
      throw VideoCompressException(CompressErrorCode.saveFailed, '$e');
    }
  }

  @override
  Future<ImageMeta> getImageInfo(String path) async {
    try {
      return await FfmpegImage.info(path);
    } on CompressException {
      rethrow;
    } catch (e) {
      throw ImageCompressException(CompressErrorCode.imageInfoFailed, '$e');
    }
  }

  @override
  Future<ImageCompressResult> compressImage(
    String path,
    ImageCompressConfig config,
    String? outputDir,
    String? outputName,
  ) async {
    try {
      return await FfmpegImage.compressFile(
        path: path,
        config: config,
        outputDir: outputDir,
        outputName: outputName,
      );
    } on CompressException {
      rethrow;
    } catch (e) {
      throw ImageCompressException(CompressErrorCode.imageCompressFailed, '$e');
    }
  }

  @override
  Future<ImageBytesResult> compressImageBytes(
    Uint8List source,
    ImageCompressConfig config,
  ) async {
    try {
      return await FfmpegImage.compressBytes(source: source, config: config);
    } on CompressException {
      rethrow;
    } catch (e) {
      throw ImageCompressException(CompressErrorCode.imageCompressFailed, '$e');
    }
  }

  int _clampDuration(int fullMs, VideoCompressConfig config) {
    final trim = config.trim;
    if (trim == null) return fullMs;
    final end = trim.endMs < fullMs ? trim.endMs : fullMs;
    final start = trim.startMs.clamp(0, end);
    return (end - start).clamp(1, fullMs);
  }
}
