import Foundation

/// Paths inside an EPUB: relative to its root, with `/` separators.
package enum ArchivePath {
  /// The archive path a reference from a document in `directory` points to, without its
  /// fragment. Nil for external links, absolute paths and anything that climbs out of the book.
  package static func resolve(_ reference: String, from directory: String) -> String? {
    let target = String(reference.prefix { $0 != "#" && $0 != "?" })
    guard !target.isEmpty, !target.hasPrefix("/"),
      target.prefixMatch(of: #/[A-Za-z][A-Za-z0-9+.\-]*:/#) == nil
    else { return nil }
    var parts = directory.split(separator: "/").map(String.init)
    for part in (target.removingPercentEncoding ?? target).split(separator: "/") {
      switch part {
      case ".":
        continue
      case "..":
        guard parts.popLast() != nil else { return nil }
      default:
        parts.append(String(part))
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "/")
  }

  package static func directory(of path: String) -> String {
    path.split(separator: "/").dropLast().joined(separator: "/")
  }
}
