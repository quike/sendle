import Foundation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "persistence")

struct JSONFile<Value: Codable>: Sendable {
  let url: URL

  /// The stored value, or nil when there is none. A file that can't be read or decoded is moved
  /// aside first, so the next save never overwrites the user's data; `onQuarantine` gets its new URL.
  func read(
    quarantiningCorruptAt date: Date,
    onQuarantine: (URL) -> Void = { _ in }
  ) -> Value? {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    } catch {
      if let moved = quarantine(at: date) { onQuarantine(moved) }
      return nil
    }
    if let value = try? Self.decoder().decode(Value.self, from: data) { return value }
    if let moved = quarantine(at: date) { onQuarantine(moved) }
    return nil
  }

  func write(_ value: Value) throws(StorageError) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder().encode(value).write(to: url, options: .atomic)
    } catch {
      let file = url.lastPathComponent
      logger.error("Could not save \(file, privacy: .public): \(error.localizedDescription)")
      throw .writeFailed(error.localizedDescription)
    }
  }

  private func quarantine(at date: Date) -> URL? {
    let folder = url.deletingLastPathComponent()
    let base =
      "\(url.deletingPathExtension().lastPathComponent).corrupt-\(Int(date.timeIntervalSince1970))"
    var target = folder.appending(path: "\(base).json")
    if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
      target = folder.appending(path: "\(base)-\(UUID().uuidString.prefix(8)).json")
    }
    let name = url.lastPathComponent
    do {
      try FileManager.default.moveItem(at: url, to: target)
      logger.warning("Moved unreadable \(name, privacy: .public) to \(target.lastPathComponent)")
      return target
    } catch {
      // Only an unwritable folder stops the move, and then saving fails too: nothing is overwritten.
      logger.error(
        "Could not move unreadable \(name, privacy: .public): \(error.localizedDescription)")
      return nil
    }
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
