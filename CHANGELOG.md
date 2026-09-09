# Changelog

## 0.1.0

Initial release of **flutter_compress_pro**.

### Platforms

- **Android** — Media3 Transformer (no FFmpeg)
- **iOS / macOS** — shared AVFoundation / ImageIO under `darwin/` (`sharedDarwinSource`)
- **Web** — WebCodecs + Canvas (no FFmpeg)
- **Windows / Linux** — FFmpeg via system `PATH`, or auto-download (BtbN GPL) on first use

### Video

- Target size / bitrate / quality % / presets
- H.264 and HEVC (H.265) with automatic H.264 fallback
- Resolution cap, trim, remove audio, audio bitrate (where the engine supports it)
- Thumbnail, media info, size estimate, progress, cancel, batch

### Image

- Target size / quality / lossless
- JPEG · PNG · WebP · HEIC (with platform fallbacks)
- Resolution cap, optional EXIF keep, `compressImageBytes`

### Notes

- Windows / Linux FFmpeg: override with `FLUTTER_COMPRESS_PRO_FFMPEG` /
  `FLUTTER_COMPRESS_PRO_FFPROBE`; disable fetch with
  `FLUTTER_COMPRESS_PRO_NO_FFMPEG_DOWNLOAD=1`.
- Auto-downloaded FFmpeg binaries are GPL (third-party); the Dart package itself
  remains MIT.
