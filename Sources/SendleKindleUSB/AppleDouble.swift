import Darwin
import Foundation

/// On FAT, macOS keeps a file's extended attributes, such as the `com.apple.provenance` it gives
/// every new file, in a `._` file beside it, which the Kindle would find among its books and
/// covers. Removing that file removes the attributes; removing the attributes leaves the file.
enum AppleDouble {
  /// Whether there was one to remove.
  @discardableResult
  static func remove(beside file: URL) -> Bool {
    unlink(file.deletingLastPathComponent().appending(path: "._" + file.lastPathComponent).path)
      == 0
  }
}
