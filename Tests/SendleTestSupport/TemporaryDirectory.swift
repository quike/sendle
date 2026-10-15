import Foundation

/// A fresh, empty folder under the system temporary directory.
public func makeTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "SendleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
