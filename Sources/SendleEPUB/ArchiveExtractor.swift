import Foundation
import SendleDomain

protocol ArchiveExtractor: Sendable {
  func extract(_ archive: URL, into folder: URL) throws(SendFailure)
}

/// Unzips with `/usr/bin/ditto`, the tool macOS itself uses.
package struct DittoExtractor: ArchiveExtractor {
  package init() {}

  package func extract(_ archive: URL, into folder: URL) throws(SendFailure) {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = [
      "-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false),
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw .localStorage(error.localizedDescription)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw .invalidBook("The EPUB file couldn't be unzipped")
    }
  }
}
