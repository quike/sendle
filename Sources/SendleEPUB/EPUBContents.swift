import Foundation

/// The files of an unzipped EPUB that belong in the archive Amazon receives.
package enum EPUBContents {
  /// Archive paths of the regular files under `root`, sorted. Leaves out `mimetype` (written
  /// first, separately), Apple's additions, and symbolic links, which could point anywhere.
  package static func entries(in root: URL) -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: root.path(percentEncoded: false))
    else { return [] }
    var entries: [String] = []
    while let path = enumerator.nextObject() as? String {
      guard enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular,
        path != "mimetype", !isAppleAddition(path)
      else { continue }
      entries.append(path)
    }
    return entries.sorted()
  }

  /// Books adds `iTunesMetadata*.plist` and other `.plist` files and `bookmarks*` at the root, and
  /// Finder adds `.DS_Store` anywhere.
  package static func isAppleAddition(_ path: String) -> Bool {
    let name = path.split(separator: "/").last.map(String.init) ?? path
    if name == ".DS_Store" { return true }
    return !path.contains("/") && (name.hasSuffix(".plist") || name.hasPrefix("bookmarks"))
  }
}
