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

/// Unzips only an EPUB's container and package documents with `/usr/bin/unzip`, so reading a
/// book's edition doesn't write out the whole book.
package struct PackageExtractor: ArchiveExtractor {
  package init() {}

  package func extract(_ archive: URL, into folder: URL) throws(SendFailure) {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/unzip")
    process.arguments = [
      "-qq", "-o", archive.path(percentEncoded: false), "META-INF/container.xml", "*.opf",
      "-d", folder.path(percentEncoded: false),
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
      throw .invalidBook("The EPUB's package couldn't be unzipped")
    }
  }
}
