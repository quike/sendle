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
  private let log: any ActivityLog
  private let chosen = OSAllocatedUnfairLock<URL?>(initialState: nil)

  public convenience init(log: any ActivityLog = NoActivityLog()) {
    self.init(folders: Self.folders, timeout: .seconds(300), log: log)
  }

  package init(folders: [URL], timeout: Duration, log: any ActivityLog = NoActivityLog()) {
    self.folders = folders
    self.timeout = timeout
    self.log = log
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
    let printed = staging.appending(path: "boko.log")
    log.info(
      .boko,
      "Running \(tool.path) convert \"\(file.url.lastPathComponent)\" "
        + "\"\(output.lastPathComponent)\"")
    let clock = ContinuousClock()
    let start = clock.now
    let outcome = try await Command.run(
      tool, ["convert", file.url.path, output.path], log: printed, timeout: timeout)
    let elapsed = Elapsed.text(clock.now - start)
    if let text = Self.output(in: printed) { log.debug(.boko, text) }
    switch outcome {
    case .cancelled:
      log.info(.boko, "Conversion cancelled")
      throw .cancelled
    case .timedOut:
      log.error(.boko, Self.timeoutMessage(after: timeout))
      throw .conversionFailed(Self.timeoutMessage(after: timeout))
    case .failedToStart(let reason):
      log.error(.boko, "Couldn't start boko: \(reason)")
      throw .conversionFailed("Couldn't start boko: \(reason)")
    case .exited(let status):
      guard status == 0 else {
        log.error(.boko, "boko stopped with status \(status) after \(elapsed)")
        throw .conversionFailed(Self.lastLines(of: printed, status: status))
      }
      guard FileManager.default.fileExists(atPath: output.path) else {
        log.error(.boko, "boko finished in \(elapsed) but made no book")
        throw .conversionFailed("boko made no book.")
      }
      log.info(.boko, "boko finished in \(elapsed)")
      return PreparedFile(url: output, format: format)
    }
  }

  private static func output(in file: URL) -> String? {
    let text = (try? String(contentsOf: file, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text?.isEmpty == false ? text : nil
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
