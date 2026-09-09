import Foundation

/// Persist a finished file where the user can find it.
///
/// - iOS: app Documents (Files app with UIFileSharingEnabled).
/// - macOS: user Downloads folder.
enum DownloadSaver {
  static func save(path: String, fileName: String?) throws -> String {
    #if os(iOS)
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    #else
    let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    #endif
    let dest = folder.appendingPathComponent(fileName ?? (path as NSString).lastPathComponent)
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.copyItem(atPath: path, toPath: dest.path)
    return dest.path
  }
}
