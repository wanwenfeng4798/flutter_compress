#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import Foundation

/// Bridges Flutter <-> the native pieces: `CompressionEngine` (transcode),
/// `MediaProbe`, `Thumbnailer`, `DownloadSaver`. Shared iOS / macOS (AVFoundation,
/// no FFmpeg).
public class FlutterCompressPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private let engine = CompressionEngine()
  private var eventSink: FlutterEventSink?
  private let workQueue = DispatchQueue(label: "flutter_compress_pro.work", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let methodChannel = FlutterMethodChannel(
      name: "flutter_compress_pro/methods", binaryMessenger: messenger)
    let eventChannel = FlutterEventChannel(
      name: "flutter_compress_pro/progress", binaryMessenger: messenger)
    let instance = FlutterCompressPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    // publish() is what earns us `detachFromEngine(for:)`, so an engine teardown
    // can stop an in-flight export instead of leaving it running.
    registrar.publish(instance)
    instance.engine.onProgress = { [weak instance] payload in
      DispatchQueue.main.async { instance?.eventSink?(payload) }
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    engine.cancelAll()
    eventSink = nil
  }

  public func onListen(
    withArguments _: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func str(_ key: String) throws -> String {
      guard let value = args[key] as? String else { throw Self.badArg(key) }
      return value
    }
    func map(_ key: String) throws -> [String: Any] {
      guard let value = args[key] as? [String: Any] else { throw Self.badArg(key) }
      return value
    }

    switch call.method {
    case "getVideoInfo":
      dispatch(result, ErrorCode.infoFailed) { try MediaProbe.videoInfo(path: try str("path")) }

    case "estimate":
      dispatch(result, ErrorCode.estimateFailed) {
        try self.engine.estimate(
          path: try str("path"), config: CompressionConfig(map: try map("config")))
      }

    case "compress":
      guard let config = try? CompressionConfig(map: map("config")),
        let id = try? str("id"), let path = try? str("path")
      else {
        result(
          FlutterError(
            code: ErrorCode.badArguments,
            message: "compress: missing id/path/config", details: nil))
        return
      }
      let outputDir = args["outputDir"] as? String, outputName = args["outputName"] as? String
      workQueue.async {
        self.engine.compress(
          id: id, path: path, config: config, outputDir: outputDir, outputName: outputName
        ) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let map): result(map)
            case .cancelled:
              result(
                FlutterError(
                  code: ErrorCode.cancelled, message: "Compression cancelled", details: nil))
            case .failure(let message):
              result(FlutterError(code: ErrorCode.compressFailed, message: message, details: nil))
            }
          }
        }
      }

    case "cancel":
      engine.cancel(id: args["id"] as? String)
      result(nil)

    case "isCompressing":
      result(engine.isCompressing())

    case "getThumbnail":
      dispatch(result, ErrorCode.thumbnailFailed) {
        try Thumbnailer.generate(
          dir: PluginFiles.cacheDir(), path: try str("path"),
          positionMs: (args["positionMs"] as? NSNumber)?.int64Value ?? 0,
          quality: (args["quality"] as? NSNumber)?.intValue ?? 80,
          maxWidth: (args["maxWidth"] as? NSNumber)?.intValue)
      }

    case "clearCache":
      PluginFiles.clearCache()
      result(nil)

    case "saveToDownloads":
      dispatch(result, ErrorCode.saveFailed) {
        try DownloadSaver.save(path: try str("path"), fileName: args["fileName"] as? String)
      }

    case "getImageInfo":
      dispatch(result, ErrorCode.imageInfoFailed) { try ImageEngine.info(path: try str("path")) }

    case "compressImageBytes":
      dispatch(result, ErrorCode.imageCompressFailed) {
        guard let data = args["bytes"] as? FlutterStandardTypedData else {
          throw Self.badArg("bytes")
        }
        return try ImageEngine.compressBytes(
          data: data.data, config: ImageConfig(map: try map("config")))
      }

    case "compressImage":
      dispatch(result, ErrorCode.imageCompressFailed) {
        try ImageEngine.compress(
          path: try str("path"),
          config: ImageConfig(map: try map("config")),
          outputDir: args["outputDir"] as? String,
          outputName: args["outputName"] as? String)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func dispatch(
    _ result: @escaping FlutterResult, _ errorCode: String, _ block: @escaping () throws -> Any?
  ) {
    workQueue.async {
      let outcome: Result<Any?, Error>
      do { outcome = .success(try block()) } catch { outcome = .failure(error) }
      DispatchQueue.main.async {
        switch outcome {
        case .success(let value):
          result(value)
        case .failure(let error):
          result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func badArg(_ key: String) -> NSError {
    NSError(
      domain: "flutter_compress_pro", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Missing or invalid argument: \(key)"])
  }
}
