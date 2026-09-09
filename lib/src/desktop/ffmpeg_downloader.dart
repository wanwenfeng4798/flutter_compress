import 'dart:ffi';
import 'dart:io';

import '../error_codes.dart';
import '../exceptions.dart';

/// Paths to resolved ffmpeg / ffprobe executables.
class FfmpegPaths {
  const FfmpegPaths({required this.ffmpeg, required this.ffprobe});
  final String ffmpeg;
  final String ffprobe;
}

/// Downloads and caches GPL FFmpeg static builds (BtbN/FFmpeg-Builds).
///
/// GPL is required for `libx264` / `libx265` (our H.264 / H.265 encoders).
/// First successful call stores binaries under the user cache dir; later runs
/// reuse them. Not used on Android / iOS / macOS / Web.
///
/// Apps that redistribute the downloaded binaries must comply with the FFmpeg
/// GPL. Prefer a system LGPL/GPL install via PATH if you need a different
/// license posture. Set `FLUTTER_COMPRESS_PRO_NO_FFMPEG_DOWNLOAD=1` to forbid fetch.
abstract final class FfmpegDownloader {
  /// Pin deliberately — bump when upgrading the downloaded FFmpeg build.
  /// Assets come from https://github.com/BtbN/FFmpeg-Builds/releases
  static const releaseTag = 'latest';
  static const buildId = 'master-latest';

  /// `gpl` includes libx264/libx265; `lgpl` would not encode H.264/H.265.
  static const licenseVariant = 'gpl';

  static Directory cacheRoot() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory(
      '$home${Platform.pathSeparator}.cache'
      '${Platform.pathSeparator}flutter_compress_pro'
      '${Platform.pathSeparator}ffmpeg'
      '${Platform.pathSeparator}$buildId',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<FfmpegPaths?> cachedBinaries() async {
    final root = cacheRoot();
    final ffmpeg = File(_binPath(root, 'ffmpeg'));
    final ffprobe = File(_binPath(root, 'ffprobe'));
    if (await ffmpeg.exists() && await ffprobe.exists()) {
      await _chmodX(ffmpeg.path);
      await _chmodX(ffprobe.path);
      return FfmpegPaths(ffmpeg: ffmpeg.path, ffprobe: ffprobe.path);
    }
    return null;
  }

  static Future<FfmpegPaths> download() async {
    final asset = _assetName();
    final url =
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/$releaseTag/$asset';
    final root = cacheRoot();
    final archivePath = '${root.path}${Platform.pathSeparator}$asset';

    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw VideoCompressException(
          CompressErrorCode.unsupported,
          'FFmpeg download failed HTTP ${response.statusCode} for $url',
        );
      }
      final sink = File(archivePath).openWrite();
      await response.pipe(sink);
      await sink.close();
    } finally {
      client?.close(force: true);
    }

    await _extract(archivePath, root);
    try {
      await File(archivePath).delete();
    } catch (_) {}

    // BtbN archives unpack to `<name>/bin/{ffmpeg,ffprobe}`.
    final binDir = await _findBinDir(root);
    if (binDir == null) {
      throw VideoCompressException(
        CompressErrorCode.unsupported,
        'Downloaded FFmpeg archive had no bin/ directory',
      );
    }

    final ffmpegSrc = File(
      '${binDir.path}${Platform.pathSeparator}ffmpeg'
      '${Platform.isWindows ? '.exe' : ''}',
    );
    final ffprobeSrc = File(
      '${binDir.path}${Platform.pathSeparator}ffprobe'
      '${Platform.isWindows ? '.exe' : ''}',
    );
    if (!await ffmpegSrc.exists() || !await ffprobeSrc.exists()) {
      throw VideoCompressException(
        CompressErrorCode.unsupported,
        'Downloaded FFmpeg archive missing ffmpeg/ffprobe binaries',
      );
    }

    final ffmpegDest = File(_binPath(root, 'ffmpeg'));
    final ffprobeDest = File(_binPath(root, 'ffprobe'));
    await ffmpegSrc.copy(ffmpegDest.path);
    await ffprobeSrc.copy(ffprobeDest.path);
    await _chmodX(ffmpegDest.path);
    await _chmodX(ffprobeDest.path);

    return FfmpegPaths(ffmpeg: ffmpegDest.path, ffprobe: ffprobeDest.path);
  }

  static String _binPath(Directory root, String name) {
    final exe = Platform.isWindows ? '$name.exe' : name;
    return '${root.path}${Platform.pathSeparator}$exe';
  }

  static String _assetName() {
    final abi = Abi.current();
    if (Platform.isWindows) {
      if (abi == Abi.windowsX64) {
        return 'ffmpeg-$buildId-win64-$licenseVariant.zip';
      }
      if (abi == Abi.windowsArm64) {
        return 'ffmpeg-$buildId-winarm64-$licenseVariant.zip';
      }
      throw VideoCompressException(
        CompressErrorCode.unsupported,
        'No auto-download FFmpeg build for Windows ABI $abi. '
        'Install FFmpeg or set FLUTTER_COMPRESS_PRO_FFMPEG.',
      );
    }
    if (Platform.isLinux) {
      if (abi == Abi.linuxX64) {
        return 'ffmpeg-$buildId-linux64-$licenseVariant.tar.xz';
      }
      if (abi == Abi.linuxArm64) {
        return 'ffmpeg-$buildId-linuxarm64-$licenseVariant.tar.xz';
      }
      throw VideoCompressException(
        CompressErrorCode.unsupported,
        'No auto-download FFmpeg build for Linux ABI $abi. '
        'Install FFmpeg or set FLUTTER_COMPRESS_PRO_FFMPEG.',
      );
    }
    throw VideoCompressException(
      CompressErrorCode.unsupported,
      'FFmpeg auto-download is only for Windows/Linux',
    );
  }

  static Future<void> _extract(String archivePath, Directory dest) async {
    if (archivePath.endsWith('.zip')) {
      // Prefer tar (Windows 10+ / bsdtar) then PowerShell.
      final tar = await Process.run('tar', [
        '-xf',
        archivePath,
        '-C',
        dest.path,
      ]);
      if (tar.exitCode == 0) return;
      final ps = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Expand-Archive -LiteralPath '$archivePath' -DestinationPath '${dest.path}' -Force",
      ]);
      if (ps.exitCode != 0) {
        throw VideoCompressException(
          CompressErrorCode.unsupported,
          'Failed to extract FFmpeg zip (tar: ${tar.stderr}; powershell: ${ps.stderr})',
        );
      }
      return;
    }
    // .tar.xz
    final result = await Process.run('tar', [
      '-xJf',
      archivePath,
      '-C',
      dest.path,
    ]);
    if (result.exitCode != 0) {
      throw VideoCompressException(
        CompressErrorCode.unsupported,
        'Failed to extract FFmpeg archive: ${result.stderr}',
      );
    }
  }

  static Future<Directory?> _findBinDir(Directory root) async {
    final direct = Directory('${root.path}${Platform.pathSeparator}bin');
    if (await direct.exists()) return direct;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory &&
          entity.path.endsWith('${Platform.pathSeparator}bin')) {
        return entity;
      }
    }
    return null;
  }

  static Future<void> _chmodX(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (_) {}
  }
}
