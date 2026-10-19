import Foundation
import SendleDomain

/// What an earlier listing of a Kindle found, so a later one reads only the books that changed.
package struct KindleListingCache: Sendable {
  private static let version = 1

  private struct Stored: Codable {
    let version: Int
    let books: [KindleBook]
  }

  private let directory: URL

  package init(directory: URL) {
    self.directory = directory.appending(path: "kindles", directoryHint: .isDirectory)
  }

  /// The books of the last saved listing by relative path, or none when there is no usable one.
  package func load(device: String) -> [String: KindleBook] {
    guard let data = try? Data(contentsOf: file(for: device)),
      let stored = try? JSONDecoder().decode(Stored.self, from: data),
      stored.version == Self.version
    else { return [:] }
    return Dictionary(stored.books.map { ($0.id.relativePath, $0) }) { first, _ in first }
  }

  /// A cache that can't be written only costs the next listing a full read.
  package func save(_ books: [KindleBook], device: String) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(Stored(version: Self.version, books: books))
      try data.write(to: file(for: device), options: .atomic)
    } catch {}
  }

  private func file(for device: String) -> URL {
    let name = device.replacingOccurrences(of: "/", with: "_").replacingOccurrences(
      of: ":", with: "_")
    return directory.appending(path: "\(name).json")
  }
}
