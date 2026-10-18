import Foundation
import SendleDomain
import os

/// Converts EPUBs with the user's own boko. Sendle never bundles it: boko is GPL.
public final class BokoConverter: FormatConverter, ToolChoice {
  /// `cargo install boko` and boko's installer both use `~/.cargo/bin`. An app opened from the
  /// Finder doesn't get the shell's PATH, so the usual folders are listed here.
  package static var folders: [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      home.appending(path: ".cargo/bin", directoryHint: .isDirectory),
      home.appending(path: ".local/bin", directoryHint: .isDirectory),
      URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory),
      URL(filePath: "/usr/local/bin", directoryHint: .isDirectory),
    ]
  }

  private let folders: [URL]
  private let timeout: Duration
  private let chosen = OSAllocatedUnfairLock<URL?>(initialState: nil)

  public convenience init() {
    self.init(folders: Self.folders, timeout: .seconds(300))
  }

  package init(folders: [URL], timeout: Duration) {
    self.folders = folders
    self.timeout = timeout
  }

  /// Looked up on every read, so a boko installed while Sendle runs is found. A chosen boko that
  /// has gone is not found: the usual folders might hold a different one.
  public var toolURL: URL? {
    if let chosenTool {
      return FileManager.default.isExecutableFile(atPath: chosenTool.path) ? chosenTool : nil
    }
    return folders.lazy.map { $0.appending(path: "boko") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  public var chosenTool: URL? { chosen.withLock { $0 } }

  public func choose(_ tool: URL?) {
    chosen.withLock { $0 = tool }
  }

  public func convert(
    _ file: PreparedFile,
    to format: FileFormat,
    in staging: URL
  ) async throws(SendFailure) -> PreparedFile {
    guard let tool = toolURL else { throw .conversionUnavailable }
    let name = file.url.deletingPathExtension().lastPathComponent
    let output = staging.appending(path: "\(name).\(format.fileExtension)")
    let log = staging.appending(path: "boko.log")
    let outcome = try await Command.run(
      tool, ["convert", file.url.path, output.path], log: log, timeout: timeout)
    switch outcome {
    case .cancelled:
      throw .cancelled
    case .timedOut:
      throw .conversionFailed(Self.timeoutMessage(after: timeout))
    case .failedToStart(let reason):
      throw .conversionFailed("Couldn't start boko: \(reason)")
    case .exited(let status):
      guard status == 0 else { throw .conversionFailed(Self.lastLines(of: log, status: status)) }
      guard FileManager.default.fileExists(atPath: output.path) else {
        throw .conversionFailed("boko made no book.")
      }
      Self.giveOwnASIN(to: output, named: name)
      return PreparedFile(url: output, format: format)
    }
  }

  /// boko gives every book the ASIN "EBOK000000", so they would all share one cover on the Kindle.
  private static func giveOwnASIN(to book: URL, named name: String) {
    guard let data = try? Data(contentsOf: book),
      let patched = AZW3Metadata.replacingASIN(in: data, with: AZW3Metadata.asin(for: name))
    else { return }
    try? patched.write(to: book, options: .atomic)
  }

  /// English in every language, like the rest of Sendle's copy.
  package static func timeoutMessage(after timeout: Duration) -> String {
    let limit = timeout.formatted(
      .units(allowed: [.minutes, .seconds], width: .wide).locale(Locale(identifier: "en_US_POSIX")))
    return "boko was still converting after \(limit), so Sendle stopped it."
  }

  /// boko ends with what went wrong; the rest of its output is progress.
  private static func lastLines(of log: URL, status: Int32) -> String {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    let lines = text.split(whereSeparator: \.isNewline).suffix(3)
    return lines.isEmpty
      ? "boko stopped with status \(status)."
      : String(lines.joined(separator: "\n").suffix(500))
  }
}
