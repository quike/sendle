import Darwin
import Foundation

/// Small metadata files from inside a book: regular files only (a link, pipe or device could
/// point anywhere or never end), and at most `limit` bytes.
enum BookFile {
  static let limit = 8_000_000

  static func contents(of url: URL) -> Data? {
    var info = stat()
    guard lstat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      info.st_size <= limit
    else { return nil }
    return try? Data(contentsOf: url)
  }
}
