import 'dart:io';

/// Scratch directory for desktop FFmpeg outputs / thumbnails.
abstract final class PluginCache {
  static Directory cacheDir() {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}flutter_compress_pro',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<void> clear() async {
    final dir = cacheDir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  static File resolveOutput({
    required String? outputDir,
    required String? outputName,
    required String sourcePath,
    required String ext,
  }) {
    final sep = Platform.pathSeparator;
    final srcName = sourcePath.split(RegExp(r'[/\\]')).last;
    final srcBase = srcName.contains('.')
        ? srcName.substring(0, srcName.lastIndexOf('.'))
        : srcName;

    String base;
    if (outputName != null && outputName.isNotEmpty) {
      final leaf = outputName.split(RegExp(r'[/\\]')).last;
      base = leaf.contains('.')
          ? leaf.substring(0, leaf.lastIndexOf('.'))
          : leaf;
    } else {
      base = '${srcBase}_${DateTime.now().millisecondsSinceEpoch}';
    }
    final fileName = '$base.$ext';

    var target = File('${cacheDir().path}$sep$fileName');
    if (outputDir != null &&
        outputDir.isNotEmpty &&
        (outputDir.startsWith('/') ||
            RegExp(r'^[A-Za-z]:[\\/]').hasMatch(outputDir))) {
      final dir = Directory(outputDir);
      dir.createSync(recursive: true);
      target = File('${dir.path}$sep$fileName');
    }

    final src = File(sourcePath).absolute.path;
    if (target.absolute.path == src) {
      target = File('${target.parent.path}$sep$base-1.$ext');
    }
    return target;
  }
}
