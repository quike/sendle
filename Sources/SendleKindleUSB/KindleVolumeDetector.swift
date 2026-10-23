import Foundation

/// Tells a drive-mounted Kindle from other volumes by its root folders (spec §2).
package enum KindleVolumeDetector {
  /// A Kindle has `documents` and `system` folders, named in lower case. "Kindle" in the volume's
  /// name stands in for a `system` folder that isn't there.
  package static func isKindle(root: URL, name: String) -> Bool {
    let folders = folderNames(in: root)
    guard folders.contains("documents") else { return false }
    return folders.contains("system") || name.range(of: "kindle", options: .caseInsensitive) != nil
  }

  /// The names as stored on disk, so a case-insensitive volume can't pass "Documents" off.
  private static func folderNames(in root: URL) -> Set<String> {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    return Set(
      entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        .map(\.lastPathComponent))
  }
}
