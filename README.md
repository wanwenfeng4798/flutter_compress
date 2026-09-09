# flutter_compress_pro

[![pub package](https://img.shields.io/pub/v/flutter_compress_pro.svg)](https://pub.dev/packages/flutter_compress_pro)
[![platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-blue.svg)](https://pub.dev/packages/flutter_compress_pro)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**One plugin to compress both video and images — on Android, iOS, Web, macOS, Windows and Linux.**

Mobile, Web and macOS use each platform's own encoders (**no FFmpeg**). Windows and
Linux use **FFmpeg**: system install on `PATH` if present, otherwise the plugin
**auto-downloads** a GPL static build on first use (cached under
`~/.cache/flutter_compress_pro/ffmpeg/`). The API still speaks *intent* — "make it
~10 MB", "half the bitrate", "under 200 KB" — instead of opaque quality knobs.

> 中文文档见 [README.zh-CN.md](README.zh-CN.md)。

**🌐 [Try the live web demo in your browser →](https://flutter-compress-pro.ckdgdgdg.workers.dev/)**

| | |
|:---:|:---:|
| ![Preview 1](https://flutter-compress-pro.ckdgdgdg.workers.dev/img/compress_en_1.jpeg) | ![Preview 2](https://flutter-compress-pro.ckdgdgdg.workers.dev/img/compress_en_2.jpeg) |

## Why flutter_compress_pro?

- 🪶 **No FFmpeg on mobile / Web / macOS** — those platforms use OS encoders only. **Windows & Linux use FFmpeg** (system `PATH`, or auto-download on first use — see setup).
- 🌍 **One API, six platforms** — the same Dart code runs on Android, iOS, Web, macOS, Windows and Linux.
- 🎯 **Hit a target size, precisely** — ask for a size and the plugin derives the bitrate with identical math on every platform.
- 🎬🖼️ **Video *and* images** — two dedicated, non-overlapping APIs (`compress` vs `compressImage`), each tuned for its medium.
- 📡 **Production-ready** — live progress, cancellation, sequential batching, and a keep-original-if-larger guard.
- 🧼 **Declares no permissions** — most compression plugins push a foreground-service notification (and its permissions) into every app that depends on them. Here background compression is opt-in and the notification is **yours**: your icon, your copy, your channel.
- 🚀 **Presets for the common cases** — `forSocialMedia()`, `maxCompression()`, `forAvatar()`; skip the tuning entirely.

## Under the hood

| Platform | Video engine | Image engine | Uses FFmpeg? | Code |
|---|---|---|---|---|
| **Android** | Media3 `Transformer` (HW-accelerated) | `Bitmap` | **No** | `android/` |
| **iOS** | `AVAssetReader` / `AVAssetWriter` | ImageIO | **No** | shared `darwin/` |
| **Web** | WebCodecs + `mp4box.js` / `mp4-muxer` | Canvas | **No** | `lib/flutter_compress_pro_web.dart` |
| **macOS** | AVFoundation (same sources as iOS) | ImageIO | **No** | shared `darwin/` |
| **Windows** | `ffmpeg` / `ffprobe` (PATH or auto-download) | FFmpeg | **Yes** | shared `lib/src/desktop/` |
| **Linux** | `ffmpeg` / `ffprobe` (PATH or auto-download) | FFmpeg | **Yes** | shared `lib/src/desktop/` |

iOS and macOS share one Swift tree via Flutter’s [`sharedDarwinSource`](https://docs.flutter.dev/packages-and-plugins/developing-packages) (same pattern as [kinetic_player/darwin](https://github.com/wanwenfeng4798/kinetic_player/tree/main/darwin)). Windows and Linux share one Dart FFmpeg backend.

## Features

### 🎬 Video — `compress`

- 🎯 **Target size**, or explicit **bitrate**, **quality %**, or **preset tiers**.
- 🧬 **HEVC (H.265) with automatic H.264 fallback** on all platforms.
- 📉 Resolution cap, frame-rate cap, audio removal, trim, `÷16` alignment.
- 🖼️ Thumbnails, media info, and a pre-flight **size estimate** (no encoding).
- 📡 Live progress, cancellation, and sequential batch.

### 🖼️ Image — `compressImage`

- 🎯 **Target size** (precise — the engine iterates on quality, then downscales) **or quality**.
- 🎞️ Formats: **JPEG · PNG · WebP · HEIC** (auto-fallback where unsupported).
- 📐 Resolution cap and optional **EXIF** keep (orientation, GPS…).
- ⚡ Millisecond-fast, single-image or batch.
- 🧠 **Compress bytes in memory** (`compressImageBytes`) — no temp file for an
  `image_picker` result, a camera frame, or a download.

## Platform support

### 🎬 Video

| Capability                                 |       Android        |        iOS        |       Web        |       macOS        |     Windows / Linux      |
|--------------------------------------------|:--------------------:|:-----------------:|:----------------:|:------------------:|:------------------------:|
| Compress (target size / bitrate / quality) |          ✅           |         ✅         |        ✅         |          ✅          |            ✅             |
| HEVC (H.265) with H.264 fallback           |          ✅           |         ✅         |        ✅         |          ✅          |            ✅             |
| Resolution cap (`maxWidth`/`maxHeight`)    |          ✅           |         ✅         |        ✅         |          ✅          |            ✅             |
| Frame-rate cap (`frameRate`)               |        ❌ ²          |         ✅         |       ❌ ²        |          ✅          |            ✅             |
| Audio: remove                              |          ✅           |         ✅         |    ❌ always off   |          ✅          |            ✅             |
| Audio: bitrate (`audioBitrateKbps`)        |        ❌ ³          |         ✅         |        ❌         |          ✅          |            ✅             |
| Trim (`trim`)                              |          ✅           |         ✅         |        ❌         |          ✅          |            ✅             |
| Thumbnail / info / estimate                |          ✅           |         ✅         |        ✅         |          ✅          |            ✅             |
| Progress / cancel / batch                  |          ✅           |         ✅         |        ✅         |          ✅          |            ✅             |
| Background compression                     |   ⚠️ opt-in ⁴         | ✅ background task |       n/a        |         n/a         |           n/a            |
| `saveToDownloads`                          |      MediaStore      |     Documents     | browser download | ~/Downloads folder |     ~/Downloads folder    |

¹ Web uses HEVC only where the browser supports WebCodecs HEVC encoding
(e.g. Safari, Chrome with HW HEVC); otherwise it falls back to H.264. Windows /
Linux use `libx265` when present (auto-download includes it) and fall back to
`libx264` if HEVC encode fails.

² Only iOS, macOS, Windows and Linux decimate frames. Media3 has no frame-dropping
effect, and the web pipeline re-encodes every decoded frame — on Android/Web,
`frameRate` only influences the bitrate/keyframe maths. Read `result.frameRate`
for what was actually written.

³ Media3 exposes no audio-encoder settings, so Android encodes AAC at its own
default. The value still shapes the `targetSizeMB` budget.

⁴ Android needs a foreground service, and its notification must be yours — pass
`androidNotification` and declare `FOREGROUND_SERVICE`. Without either, the encode
runs foreground-only; nothing throws. See
[Background compression on Android](#background-compression-on-android). iOS needs
nothing (`beginBackgroundTask`: no UI, no permission). Desktop has no equivalent.

Anything marked ❌ is **ignored**, not approximated — the result object reports what
actually happened (`result.frameRate`, `result.hasAudio`, `result.durationMs`).

### 🖼️ Image

| Capability                              |  Android   |    iOS    |       Web        |  macOS  | Windows / Linux |
|-----------------------------------------|:----------:|:---------:|:----------------:|:-------:|:---------------:|
| Compress (target size / quality)        |     ✅      |     ✅     |        ✅         |    ✅    |        ✅        |
| JPEG / PNG / WebP                       |     ✅      |     ✅     |        ✅         |    ✅    |        ✅        |
| HEIC                                    |    ⚠️ ¹    |     ✅     |        ❌         |    ✅    |     ❌ → JPEG     |
| Resolution cap (`maxWidth`/`maxHeight`) |     ✅      |     ✅     |        ✅         |    ✅    |        ✅        |
| Keep EXIF (`keepExif`)                  | ⚠️ JPEG only ² |  ✅   |        ❌         |    ✅    |  ⚠️ JPEG ³       |
| Compress bytes (`compressImageBytes`)   |     ✅      |     ✅     |        ✅         |    ✅    |        ✅        |
| `saveToDownloads`                       | MediaStore | Documents | browser download | ~/Downloads | ~/Downloads |

¹ Android only writes HEIC when a device HEIC encoder is present; otherwise the
engine falls back to JPEG (the actual format is reported on the result). Windows /
Linux always re-encode HEIC requests as JPEG.

² Android copies 48 EXIF tags (camera, exposure, lens, GPS, timestamps) into JPEG
output. iOS / macOS pass the source's metadata through wholesale. Web's canvas
re-encode strips metadata entirely — there is no way around it.

³ Windows / Linux use FFmpeg `-map_metadata` (keep) or `-map_metadata -1` (strip);
JPEG is reliable; other formats depend on the muxer.

## Install

```yaml
dependencies:
  flutter_compress_pro: ^0.1.0
```

## Integrate with an AI assistant

Point Claude Code, Cursor, Copilot or any LLM at
**[llm-guide.md](llm-guide.md)** — the guide walks the assistant through the complete integration.

> Read https://raw.githubusercontent.com/wanwenfeng4798/flutter_compress_pro/master/llm-guide.md
> and add video compression to this screen.

## Quick start

```dart
import 'package:flutter_compress_pro/flutter_compress_pro.dart';

final result = await FlutterCompress.instance.compress(
  inputPath,
  const VideoCompressConfig(
    targetSizeMB: 10,          // highest-priority size control
    codec: VideoCodec.h265,    // auto-falls-back to H.264
    maxWidth: 1280,            // downscale-only
    maxHeight: 1280,
  ),
  onProgress: (p) => debugPrint('${(p.progress * 100).toStringAsFixed(0)}%'),
);

print('saved ${result.savedPercent.toStringAsFixed(1)}% → ${result.outputPath}');
```

## Configuration

`VideoCompressConfig` — set **one** size/quality control; priority is:

`targetSizeMB` → `videoBitrateKbps` → `qualityPercent` → `quality`

| Field                              | Meaning                                                        |
|------------------------------------|----------------------------------------------------------------|
| `targetSizeMB`                     | Desired output size; the plugin derives the bitrate.           |
| `videoBitrateKbps`                 | Explicit average video bitrate.                                |
| `qualityPercent`                   | Output bitrate = `percent%` of the **source** bitrate (1–100). |
| `quality`                          | Preset tier: `high` / `medium` / `low` / `veryLow`.            |
| `codec`                            | `h265` (default, auto-fallback) or `h264`.                     |
| `maxWidth` / `maxHeight`           | Cap dimensions; aspect kept, only ever scales down.            |
| `frameRate`                        | Cap the fps.                                                   |
| `removeAudio` / `audioBitrateKbps` | Drop or re-encode audio.                                       |
| `trim`                             | `TrimRange(startMs, endMs)`.                                   |
| `alignment`                        | `auto16` (default) rounds to `÷16` to avoid edge artifacts.    |
| `keepOriginalIfLarger`             | Return the original if compression wouldn't help.              |
| `minSavingsPercent`                | Return the original unless compression saves at least this much (0–99, default 0). At `5`, an output that shaves only 3% comes back `skipped`. |
| `androidNotification`              | Opt into background compression by supplying the foreground-service notification (icon, title, text, channel). `null` (default) → no service. Android only. |
| `container`                        | `auto` (default) keeps the source container where the platform can (iOS `.mov`/`.mp4`; Android/Web → `.mp4`), or `mp4` to force it. |

## API

```dart
final api = FlutterCompress.instance;

// Probe & estimate (no encoding)
final VideoInfo info = await api.getVideoInfo(path);
final CompressionEstimate est = await api.estimate(path, config);

// Compress (single)
final token = CancellationToken();
final result = await api.compress(
  path, config,
  onProgress: (p) => print(p.progress),   // 0.0–1.0
  cancellationToken: token,
  outputDirectory: dir,                    // optional
  outputName: 'my_clip',                   // optional; no extension → auto-added
);
await token.cancel();                      // aborts the job above

// Batch (sequential), thumbnails, housekeeping
await api.compressAll(paths, config);
final String thumb = await api.getThumbnail(path, positionMs: 1000, maxWidth: 320);
final String saved = await api.saveToDownloads(result.outputPath);
await api.releaseOutput(result.outputPath);  // frees one result (see below)
await api.clearCache();

// Global progress feed (e.g. for a batch UI)
api.progressStream.listen((p) => print('${p.id} ${p.progress}'));
```

## Images

The image API is fully separate from the video one.

```dart
final api = FlutterCompress.instance;

// Probe (no encoding)
final ImageMeta meta = await api.getImageInfo(path);

// Compress to a target size (precise — images encode fast, so the engine
// binary-searches quality, then downscales if needed to land under it).
// With no `format`, the output keeps the source's format.
final ImageCompressResult r = await api.compressImage(
  path,
  const ImageCompressConfig(
    targetSizeKB: 200,          // highest-priority size control
    maxWidth: 2560,             // downscale-only
    maxHeight: 2560,
  ),
  outputDirectory: dir,         // optional; null → plugin cache
  outputName: 'my_photo',       // optional; no extension → auto-added
);
print('${r.format} ${r.width}x${r.height} • saved ${r.savedPercent.toStringAsFixed(1)}%');

// Convert format, control quality, go lossless, or batch:
await api.compressImage(path, const ImageCompressConfig(format: ImageFormat.webp, quality: 80));
await api.compressImageLossless(path);   // keep source format, pixel-for-pixel

// Presets — no tuning needed.
await api.compressImage(path, const ImageCompressConfig.forAvatar());
await api.compressImage(path, const ImageCompressConfig.forSocialMedia());

// Already have the bytes? Skip the temp file entirely.
final ImageBytesResult b = await api.compressImageBytes(
  bytes,                                 // e.g. await xFile.readAsBytes()
  const ImageCompressConfig(targetSizeKB: 200),
);
uploadBytes(b.bytes);                    // nothing written to disk, nothing to release

// Batch with progress, cancellation, and per-file error tolerance:
final token = CancellationToken();
final results = await api.compressImages(
  paths,
  const ImageCompressConfig(targetSizeKB: 300),
  onItemDone: (i, total) => print('${i + 1}/$total'),
  cancellationToken: token,
  continueOnError: true,                  // a bad file won't discard the rest
  onItemError: (i, path, e) => print('skipped $path: $e'),
);
```

## Errors

Everything throws a typed exception — a raw `PlatformException` never escapes.

```dart
try {
  await api.compressImage(path, config);
} on CompressCancelled {
  // cancelled (video or image)
} on ImageCompressException catch (e) {
  if (e.code == CompressErrorCode.imageCompressFailed) { /* … */ }
} on CompressException catch (e) {
  // any other failure from either API
}
```

Match on `CompressErrorCode` rather than raw strings — the constants are mirrored
on all six platforms, and the values are part of the public contract.

`CompressException` is the base; `VideoCompressException` / `ImageCompressException`
narrow it, and `CompressCancelled` is a marker both cancel types implement.

`ImageCompressConfig` — priority is `lossless` → `targetSizeKB` → `quality`:

| Field                    | Meaning                                                       |
|--------------------------|---------------------------------------------------------------|
| `format`                 | `null` (default) keeps the **source** format; or `jpeg` / `png` / `webp` / `heic`. |
| `targetSizeKB`           | Desired output size; the engine iterates to land at/under it. |
| `quality`                | 1–100, used when `targetSizeKB` is null (ignored for PNG).    |
| `lossless`               | Encode losslessly (PNG truly lossless; JPEG stays JPEG at max quality). Ignores `quality`/`targetSizeKB`. |
| `maxWidth` / `maxHeight` | Cap dimensions; aspect kept, only scales down.                |
| `keepExif`               | Keep EXIF (orientation, GPS, …); default strips it.           |
| `keepOriginalIfLarger`   | Return the original (marked `skipped`) if compression wouldn't shrink it. Default on. |
| `minSavingsPercent`      | Return the original unless compression saves at least this much (0–99, default 0). |

## Platform setup

- **Android** — min SDK 24, `compileSdk 37`. **Declares no permissions.** See
  [Android permissions](#android-permissions) and
  [Background compression](#background-compression-on-android).
- **iOS** — min 13.0. Uses `beginBackgroundTask` for a short background grace
  period. To make `saveToDownloads` files visible in the Files app, add
  `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` to `Info.plist`.
- **Web** — needs WebCodecs (Chrome/Edge 94+, Safari 16.4+). Inputs/outputs are
  `blob:` URLs; the vendored demux/mux JS (216 KB, see
  [THIRD_PARTY_NOTICES](assets/THIRD_PARTY_NOTICES.md)) loads lazily on first
  video compression — image compression never fetches it.
  Pick a file via `file_picker` and pass `xFile.path` (a `blob:` URL on web).
  **Call `releaseOutput(result.outputPath)`** once you've downloaded or uploaded a
  result — the browser otherwise holds the whole encoded file in memory for the
  life of the page (`clearCache()` releases every output at once).
  Try the [live demo](https://flutter-compress-pro.ckdgdgdg.workers.dev/) to see it in action.

### Android permissions

**This plugin declares no permissions.** Compression is codec work on a file you
already handed over; it needs none, and manifest merging would push anything
declared here into every app that depends on the plugin.

The one thing it does declare is a `<service>` — a declaration, not a permission,
so it has no bearing on store review. It has to be in the manifest for the class
to be startable, and it is **inert** unless you both declare `FOREGROUND_SERVICE`
*and* pass `androidNotification`. See
[Background compression](#background-compression-on-android).

The one exception worth knowing about: `saveToDownloads()` on **Android 9 and
below** writes to the public Downloads folder directly and therefore needs the
legacy permission. API 29+ goes through MediaStore and needs nothing.

```xml
<!-- Only if you call saveToDownloads() and support Android 9 or below. -->
<uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />
```

Without it, `saveToDownloads()` throws `CompressErrorCode.permissionDenied` with a
message saying exactly this. The plugin never requests runtime permissions for
you — when to ask the user is a product decision.

The example app declares **zero** permissions, which is the point: it compresses
video and images with nothing granted.

### Background compression on Android

Android suspends work when your app leaves the foreground, so a long encode needs
a foreground service — and a foreground service must show a notification. The
plugin ships the service but **supplies no notification of its own**: the icon,
wording and channel name are prominent UI that belongs to your app, not to a
library.

So it is opt-in in two steps. Declare the permissions:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<!-- Optional, Android 13+ runtime permission. Without it the service still runs,
     the notification is just not shown. Request it with a permissions package. -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

…and pass the notification:

```dart
await FlutterCompress.instance.compress(
  path,
  const VideoCompressConfig(
    targetSizeMB: 10,
    androidNotification: AndroidNotification(
      smallIcon: 'drawable/ic_compress',   // your resource
      title: 'Compressing video',          // your copy, your localisation
      text: 'Tap to return to the app',
      channelName: 'Media processing',     // shown in system settings
    ),
  ),
);
```

`smallIcon` is `"type/name"` resolved against **your** resources
(`"mipmap/ic_launcher"` works too; a bare `"ic_compress"` means
`"drawable/ic_compress"`).

**No service starts unless all three hold**, and a miss is never an error — the
plugin logs and the encode continues foreground-only:

| Missing | Result |
|---|---|
| `androidNotification` omitted | No service. This is the default |
| `smallIcon` doesn't resolve in your app | No service (a bogus icon shows blank or throws on some OEMs) |
| `FOREGROUND_SERVICE` not declared | No service |

iOS needs none of this: the plugin requests a short background window with
`beginBackgroundTask`, which shows no UI and needs no permission. `androidNotification`
is ignored there and on web.

#### The service is visible in your APK

The `<service>` merges into your manifest, is compiled into the APK's binary
`AndroidManifest.xml`, and is readable through `PackageManager` — so APK
inspectors such as **LibChecker** list
`com.compress.all.flutter_compress_pro.CompressionService`, and can fingerprint this
plugin from it. Nothing runs, but the name is there.

To trace *any* merged element back to whichever dependency added it:

```
<your-app>/build/app/outputs/logs/manifest-merger-<variant>-report.txt
```

Each entry names its origin, e.g.
`service#…CompressionService  ADDED from [:flutter_compress_pro]`.

If your app never wants background compression, drop the declaration — that
removes it from the component listing too:

```xml
<service android:name="com.compress.all.flutter_compress_pro.CompressionService"
    tools:node="remove" />
```

### Native dependencies

| Dependency | Version | Unshrunk size | Notes |
|---|---|---|---|
| `androidx.media3:media3-transformer` + `-effect`, `-common`, `-muxer` | 1.10.1 | ~AARs including transitive ExoPlayer modules | The video pipeline. R8 removes a large share of this; measure your own release build |
| `androidx.core:core-ktx` | 1.19.0 | ~0.2 MB | Almost always already present — Flutter pulls `androidx.core` in |
| `org.jetbrains.kotlinx:kotlinx-coroutines-android` | 1.11.0 | ~20 KB | Also usually already present |

iOS, macOS and web add **no** third-party native dependencies: Apple platforms use
AVFoundation / ImageIO; web uses WebCodecs plus two vendored JS bundles (see
[THIRD_PARTY_NOTICES](assets/THIRD_PARTY_NOTICES.md)).

**Windows / Linux** prefer `ffmpeg` / `ffprobe` on `PATH`. If missing, the
plugin downloads a **GPL** static build from
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds/releases) on first
use (~100–200 MB; needs `libx264`/`libx265`) and caches it under
`~/.cache/flutter_compress_pro/ffmpeg/`. Redistributing that binary means complying
with FFmpeg’s GPL. Override paths with `FLUTTER_COMPRESS_PRO_FFMPEG` /
`FLUTTER_COMPRESS_PRO_FFPROBE`, or set `FLUTTER_COMPRESS_PRO_NO_FFMPEG_DOWNLOAD=1` to
forbid network fetch.

Versions are pinned to the ones actually tested rather than floated. Gradle
resolves conflicts upward, so an app declaring a newer Media3 still wins — but
the plugin won't silently adopt one. (Media3 changed the meaning of a
muxer `Factory` parameter inside its 1.x line once, which truncated every
output to 30 seconds while compiling perfectly cleanly.)

## Platform setup

### Windows / Linux (FFmpeg)

Optional — install system FFmpeg to skip the first-run download:

```bash
# Debian/Ubuntu
sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# Windows: https://ffmpeg.org/download.html and add to PATH
```

Environment:

```bash
# Point at your own binaries
export FLUTTER_COMPRESS_PRO_FFMPEG=/usr/local/bin/ffmpeg
export FLUTTER_COMPRESS_PRO_FFPROBE=/usr/local/bin/ffprobe

# Never download (fail if not on PATH)
export FLUTTER_COMPRESS_PRO_NO_FFMPEG_DOWNLOAD=1
```

### macOS / iOS

No extra install — shared `darwin/` AVFoundation / ImageIO sources.

**macOS App Sandbox:** if the host app uses a file picker (e.g. `file_picker`),
add user-selected file access to both Debug and Release entitlements, or you get
`ENTITLEMENT_NOT_FOUND`:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<!-- optional: saveToDownloads() -->
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

## Known limitations

- **Web (v1):** audio is dropped and `trim` is not yet applied.
- **Windows / Linux:** codec features follow the FFmpeg build in use (auto-download
  is GPL with libx264/libx265). HEIC image encode falls back to JPEG.

## License

MIT — see [LICENSE](LICENSE). Auto-downloaded FFmpeg on Windows/Linux is **GPL**
(third-party); see [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds).
