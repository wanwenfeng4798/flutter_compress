import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../error_codes.dart';
import '../exceptions.dart';
import '../models.dart';
import 'ffmpeg_binaries.dart';

/// Result of an FFmpeg video encode attempt.
class FfmpegCompressResult {
  const FfmpegCompressResult({
    required this.cancelled,
    this.usedCodec = 'h264',
  });
  final bool cancelled;

  /// Codec actually written (`h264` / `h265`), after any fallback.
  final String usedCodec;
}

/// Video probe / compress / thumbnail via ffprobe + ffmpeg.
abstract final class FfmpegVideo {
  static bool? _hevcEncoderAvailable;

  static Future<VideoInfo> probe(String path) async {
    await FfmpegBinaries.ensureAvailable();
    final result = await Process.run(FfmpegBinaries.ffprobe, [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    if (result.exitCode != 0) {
      throw VideoCompressException(
        CompressErrorCode.infoFailed,
        'ffprobe failed: ${result.stderr}',
      );
    }
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final streams = (json['streams'] as List?) ?? const [];
    Map<String, dynamic>? video;
    for (final s in streams) {
      final m = s as Map<String, dynamic>;
      if (m['codec_type'] == 'video') {
        video = m;
        break;
      }
    }
    if (video == null) {
      throw VideoCompressException(
        CompressErrorCode.infoFailed,
        'No video stream in $path',
      );
    }
    final format = (json['format'] as Map?)?.cast<String, dynamic>() ?? {};
    final durationSec =
        double.tryParse('${format['duration']}') ??
        double.tryParse('${video['duration']}') ??
        0;
    final sizeBytes =
        int.tryParse('${format['size']}') ?? (await File(path).length());
    final bitRate =
        int.tryParse('${format['bit_rate']}') ??
        int.tryParse('${video['bit_rate']}') ??
        0;
    final fps = _parseFps(video['avg_frame_rate'] ?? video['r_frame_rate']);
    final codecName = '${video['codec_name'] ?? ''}';
    final codec = codecName.contains('265') || codecName.contains('hevc')
        ? 'h265'
        : codecName.contains('264') || codecName.contains('avc')
        ? 'h264'
        : codecName.isEmpty
        ? null
        : codecName;
    final tags = video['tags'];
    final rotation = tags is Map
        ? int.tryParse('${tags['rotate'] ?? 0}') ?? 0
        : 0;

    return VideoInfo(
      path: path,
      width: (video['width'] as num?)?.toInt() ?? 0,
      height: (video['height'] as num?)?.toInt() ?? 0,
      durationMs: (durationSec * 1000).round(),
      sizeBytes: sizeBytes,
      bitrateKbps: bitRate ~/ 1000,
      frameRate: fps,
      codec: codec,
      rotation: rotation,
    );
  }

  static Future<FfmpegCompressResult> compress({
    required String id,
    required String inputPath,
    required String outputPath,
    required VideoCompressConfig config,
    required VideoInfo info,
    required int targetWidth,
    required int targetHeight,
    required int videoBitrateBps,
    required int durationMs,
    required void Function(double progress) onProgress,
    required void Function(Process process) onProcess,
    required bool Function() isCancelled,
  }) async {
    await FfmpegBinaries.ensureAvailable();
    if (isCancelled()) {
      return const FfmpegCompressResult(cancelled: true);
    }

    final wantHevc = config.codec == VideoCodec.h265;
    final tryHevc = wantHevc && await _hasHevcEncoder();

    Future<FfmpegCompressResult> run(bool hevc) => _runEncode(
      inputPath: inputPath,
      outputPath: outputPath,
      config: config,
      info: info,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      videoBitrateBps: videoBitrateBps,
      durationMs: durationMs,
      useHevc: hevc,
      onProgress: onProgress,
      onProcess: onProcess,
      isCancelled: isCancelled,
    );

    if (tryHevc) {
      try {
        return await run(true);
      } on VideoCompressException {
        // Match Android/iOS/Web: fall back to H.264 when HEVC encode fails.
        try {
          await File(outputPath).delete();
        } catch (_) {}
        if (isCancelled()) {
          return const FfmpegCompressResult(cancelled: true);
        }
        return run(false);
      }
    }
    return run(false);
  }

  static Future<FfmpegCompressResult> _runEncode({
    required String inputPath,
    required String outputPath,
    required VideoCompressConfig config,
    required VideoInfo info,
    required int targetWidth,
    required int targetHeight,
    required int videoBitrateBps,
    required int durationMs,
    required bool useHevc,
    required void Function(double progress) onProgress,
    required void Function(Process process) onProcess,
    required bool Function() isCancelled,
  }) async {
    final vCodec = useHevc ? 'libx265' : 'libx264';
    final usedCodec = useHevc ? 'h265' : 'h264';
    final args = <String>[
      '-y',
      '-hide_banner',
      '-progress',
      'pipe:1',
      '-nostats',
    ];
    final trim = config.trim;
    if (trim != null) {
      args.addAll(['-ss', _sec(trim.startMs), '-to', _sec(trim.endMs)]);
    }
    args.addAll(['-i', inputPath]);

    final filters = <String>[];
    if (targetWidth > 0 &&
        targetHeight > 0 &&
        (targetWidth != info.width || targetHeight != info.height)) {
      filters.add('scale=$targetWidth:$targetHeight');
    }
    if (config.frameRate != null) {
      filters.add('fps=${config.frameRate}');
    }
    if (filters.isNotEmpty) {
      args.addAll(['-vf', filters.join(',')]);
    }

    args.addAll([
      '-c:v',
      vCodec,
      '-b:v',
      '$videoBitrateBps',
      '-pix_fmt',
      'yuv420p',
      '-movflags',
      '+faststart',
    ]);
    if (useHevc) {
      // Quieter x265 logs; tag for Apple players.
      args.addAll(['-tag:v', 'hvc1', '-x265-params', 'log-level=error']);
    }

    if (config.removeAudio) {
      args.add('-an');
    } else {
      final aBps = (config.audioBitrateKbps ?? 128) * 1000;
      args.addAll(['-c:a', 'aac', '-b:a', '$aBps']);
    }
    args.add(outputPath);

    final process = await Process.start(FfmpegBinaries.ffmpeg, args);
    onProcess(process);

    var stderrBuf = '';
    final progressSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('out_time_ms=')) {
            final us = int.tryParse(line.substring('out_time_ms='.length));
            if (us != null && durationMs > 0) {
              final ms = us / 1000.0;
              onProgress((ms / durationMs).clamp(0.0, 0.99));
            }
          } else if (line == 'progress=end') {
            onProgress(1.0);
          }
        });

    process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBuf += chunk;
      if (stderrBuf.length > 8000) {
        stderrBuf = stderrBuf.substring(stderrBuf.length - 4000);
      }
    });

    final exitCode = await process.exitCode;
    await progressSub.cancel();

    if (isCancelled() || exitCode < 0) {
      try {
        await File(outputPath).delete();
      } catch (_) {}
      return FfmpegCompressResult(cancelled: true, usedCodec: usedCodec);
    }
    if (exitCode != 0) {
      throw VideoCompressException(
        CompressErrorCode.compressFailed,
        'ffmpeg ($vCodec) exited $exitCode: $stderrBuf',
      );
    }
    return FfmpegCompressResult(cancelled: false, usedCodec: usedCodec);
  }

  static Future<bool> _hasHevcEncoder() async {
    final cached = _hevcEncoderAvailable;
    if (cached != null) return cached;
    try {
      final result = await Process.run(FfmpegBinaries.ffmpeg, [
        '-hide_banner',
        '-encoders',
      ]);
      final out = '${result.stdout}\n${result.stderr}';
      _hevcEncoderAvailable = out.contains('libx265');
    } catch (_) {
      _hevcEncoderAvailable = false;
    }
    return _hevcEncoderAvailable!;
  }

  static Future<String> thumbnail({
    required String path,
    required int positionMs,
    required int quality,
    required int? maxWidth,
    required Directory outDir,
  }) async {
    await FfmpegBinaries.ensureAvailable();
    final out = File(
      '${outDir.path}${Platform.pathSeparator}'
      'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final q = (31 - (quality.clamp(1, 100) / 100.0 * 30)).round().clamp(2, 31);
    final args = <String>[
      '-y',
      '-ss',
      _sec(positionMs),
      '-i',
      path,
      '-frames:v',
      '1',
      '-q:v',
      '$q',
    ];
    if (maxWidth != null && maxWidth > 0) {
      args.addAll(['-vf', 'scale=$maxWidth:-2']);
    }
    args.add(out.path);
    final result = await Process.run(FfmpegBinaries.ffmpeg, args);
    if (result.exitCode != 0 || !await out.exists()) {
      throw VideoCompressException(
        CompressErrorCode.thumbnailFailed,
        'ffmpeg thumbnail failed: ${result.stderr}',
      );
    }
    return out.path;
  }

  static double? _parseFps(dynamic raw) {
    final s = '$raw';
    if (s.contains('/')) {
      final parts = s.split('/');
      final a = double.tryParse(parts[0]);
      final b = double.tryParse(parts[1]);
      if (a != null && b != null && b != 0) return a / b;
    }
    return double.tryParse(s);
  }

  static String _sec(int ms) => (ms / 1000.0).toStringAsFixed(3);
}
