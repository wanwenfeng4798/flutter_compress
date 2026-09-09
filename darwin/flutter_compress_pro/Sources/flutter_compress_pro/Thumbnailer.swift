import AVFoundation
import Foundation
import ImageIO

/// Extracts a single JPEG thumbnail frame from a video.
/// Uses ImageIO on both iOS and macOS (no UIKit / AppKit).
enum Thumbnailer {
  static func generate(
    dir: URL, path: String, positionMs: Int64, quality: Int, maxWidth: Int?
  ) throws -> String {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    generator.appliesPreferredTrackTransform = true
    if let maxWidth = maxWidth {
      generator.maximumSize = CGSize(width: maxWidth, height: 0)
    }
    let cg = try generator.copyCGImage(
      at: CMTime(value: positionMs, timescale: 1000), actualTime: nil)
    guard let data = jpegData(from: cg, quality: CGFloat(quality) / 100.0) else {
      throw NSError(
        domain: "flutter_compress_pro", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
    }
    let out = dir.appendingPathComponent("thumb_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
    try data.write(to: out)
    return out.path
  }

  private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
    let data = NSMutableData()
    // "public.jpeg" UTI — available on our iOS 13 / macOS 10.15 floors
    // without UniformTypeIdentifiers (which needs iOS 14 / macOS 11).
    guard
      let dest = CGImageDestinationCreateWithData(
        data, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    let props: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality
    ]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }
}
