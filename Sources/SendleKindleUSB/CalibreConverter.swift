import Foundation
import SendleDomain

/// Converts EPUBs with the user's own Calibre (`ebook-convert`). Sendle never bundles it: Calibre
/// is GPL.
public struct CalibreConverter: FormatConverter {
  private static let tool = "calibre.app/Contents/MacOS/ebook-convert"

  private let folders: [URL]
  private let timeout: Duration

  public init() {
    self.init(
      folders: [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        FileManager.default.homeDirectoryForCurrentUser.appending(
          path: "Applications", directoryHint: .isDirectory),
      ],
      timeout: .seconds(300))
  }

  package init(folders: [URL], timeout: Duration) {
    self.folders = folders
    self.timeout = timeout
  }

  /// Looked up on every read, so a Calibre installed while Sendle runs is found.
  public var toolURL: URL? {
    folders.lazy.map { $0.appending(path: Self.tool) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  public func convert(
    _ file: PreparedFile,
    to format: FileFormat,
    in staging: URL
  ) async throws(SendFailure) -> PreparedFile {
    guard let tool = toolURL else { throw .conversionUnavailable }
    let name = file.url.deletingPathExtension().lastPathComponent
    let output = staging.appending(path: "\(name).\(format.fileExtension)")
    let log = staging.appending(path: "ebook-convert.log")
    let outcome = try await Command.run(
      tool, [file.url.path, output.path, "--output-profile", "kindle"], log: log, timeout: timeout)
    switch outcome {
    case .cancelled:
      throw .cancelled
    case .timedOut:
      let limit = timeout.formatted(.units(allowed: [.minutes, .seconds], width: .wide))
      throw .conversionFailed("Calibre was still converting after \(limit), so Sendle stopped it.")
    case .failedToStart(let reason):
      throw .conversionFailed("Couldn't start Calibre: \(reason)")
    case .exited(let status):
      guard status == 0 else { throw .conversionFailed(Self.lastLines(of: log, status: status)) }
      guard FileManager.default.fileExists(atPath: output.path) else {
        throw .conversionFailed("Calibre made no book.")
      }
      return PreparedFile(url: output, format: format)
    }
  }

  /// Calibre ends with what went wrong; the rest of its output is progress.
  private static func lastLines(of log: URL, status: Int32) -> String {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    let lines = text.split(whereSeparator: \.isNewline).suffix(3)
    return lines.isEmpty
      ? "ebook-convert stopped with status \(status)."
      : String(lines.joined(separator: "\n").suffix(500))
  }
}
