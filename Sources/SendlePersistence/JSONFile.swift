import Foundation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "persistence")

struct JSONFile<Value: Codable>: Sendable {
  let url: URL

  /// The stored value, or nil when there is none. An unreadable file is moved aside first, so
  /// the user's data is kept for inspection instead of being overwritten by the next save.
  func read(quarantiningCorruptAt date: Date) -> Value? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    if let value = try? Self.decoder().decode(Value.self, from: data) { return value }
    quarantine(at: date)
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

  private func quarantine(at date: Date) {
    let stamp = Int(date.timeIntervalSince1970)
    let name = "\(url.deletingPathExtension().lastPathComponent).corrupt-\(stamp).json"
    try? FileManager.default.moveItem(
      at: url, to: url.deletingLastPathComponent().appending(path: name))
    logger.warning("Moved unreadable \(self.url.lastPathComponent, privacy: .public) to \(name)")
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
