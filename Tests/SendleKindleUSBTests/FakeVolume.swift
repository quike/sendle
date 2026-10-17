import Foundation
import SendleTestSupport

/// A temporary folder laid out like a volume's root, holding `folders`.
func makeVolumeRoot(folders: [String] = ["documents", "system"]) throws -> URL {
  let root = try makeTemporaryDirectory()
  for folder in folders {
    try FileManager.default.createDirectory(
      at: root.appending(path: folder), withIntermediateDirectories: false)
  }
  return root
}
