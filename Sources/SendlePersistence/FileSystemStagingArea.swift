import Foundation
import SendleDomain

/// One throwaway folder per send, under a single root that is safe to wipe.
public struct FileSystemStagingArea: StagingArea {
  public let root: URL

  public init(
    root: URL = FileManager.default.temporaryDirectory
      .appending(path: "Sendle-staging", directoryHint: .isDirectory)
  ) {
    self.root = root
  }

  public func makeDirectory() throws(SendFailure) -> URL {
    let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw .localStorage(error.localizedDescription)
    }
    return directory
  }

  public func writeFile(
    named name: String,
    contents: Data,
    in directory: URL
  ) throws(SendFailure) -> URL {
    let file = directory.appending(path: name)
    do {
      try contents.write(to: file, options: .atomic)
    } catch {
      throw .localStorage(error.localizedDescription)
    }
    return file
  }

  /// Refuses anything outside `root`: a wrong URL here must never delete a book.
  public func remove(_ directory: URL) {
    let target = directory.standardizedFileURL
    let rootComponents = root.standardizedFileURL.pathComponents
    guard target.pathComponents.count > rootComponents.count,
      Array(target.pathComponents.prefix(rootComponents.count)) == rootComponents
    else { return }
    try? FileManager.default.removeItem(at: target)
  }

  /// Clears folders left behind when a send was interrupted, e.g. by a crash.
  public func purge() {
    try? FileManager.default.removeItem(at: root)
  }
}
