import Foundation
import SendleDomain

/// Where Books keeps its library database.
public enum LibraryLocation: Hashable, Sendable {
  /// A folder of `BKLibrary-*.sqlite` files, of which the newest is read.
  case directory(URL)
  /// One database file, such as a fixture for manual checks.
  case file(URL)

  package static let environmentKey = "SENDLE_LIBRARY_DB"

  /// Books' own folder, unless `SENDLE_LIBRARY_DB` names a database file.
  public static func standard(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> LibraryLocation {
    if let override = environment[environmentKey], !override.isEmpty {
      return .file(URL(filePath: override))
    }
    return .directory(
      URL.homeDirectory.appending(
        path: "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary",
        directoryHint: .isDirectory))
  }

  package func databaseURL() throws(LibraryError) -> URL {
    switch self {
    case .file(let url):
      guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        throw .notFound
      }
      return url
    case .directory(let directory):
      let contents: [URL]
      do {
        contents = try FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
      } catch let error as CocoaError where error.code == .fileReadNoPermission {
        throw .accessDenied
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        throw .notFound
      } catch {
        throw .unreadable(error.localizedDescription)
      }
      guard let newest = contents.filter(Self.isLibraryDatabase).max(by: Self.isOlder) else {
        throw .notFound
      }
      return newest
    }
  }

  /// The folder to watch for changes, and which of its file names belong to the library.
  package var watched: (directory: URL, isLibraryFile: @Sendable (String) -> Bool) {
    switch self {
    case .file(let url):
      let name = url.lastPathComponent
      return (url.deletingLastPathComponent(), { $0 == name || $0 == name + "-wal" })
    case .directory(let directory):
      return (
        directory,
        { $0.hasPrefix("BKLibrary-") && ($0.hasSuffix(".sqlite") || $0.hasSuffix(".sqlite-wal")) }
      )
    }
  }

  private static func isLibraryDatabase(_ url: URL) -> Bool {
    url.lastPathComponent.hasPrefix("BKLibrary-") && url.pathExtension == "sqlite"
  }

  private static func isOlder(_ lhs: URL, _ rhs: URL) -> Bool {
    let (left, right) = (modified(lhs), modified(rhs))
    return left == right ? lhs.lastPathComponent < rhs.lastPathComponent : left < right
  }

  private static func modified(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      ?? .distantPast
  }
}
