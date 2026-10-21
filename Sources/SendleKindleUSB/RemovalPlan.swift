import SendleDomain

/// The files of one Kindle book that deleting it takes, found before anything is touched.
package struct RemovalPlan: Equatable, Sendable {
  package enum Part: Equatable, Sendable {
    case book(String)
    case appleDouble(String)
    case sidecar(String)
    case thumbnail(String)
    case thumbnailAppleDouble(String)

    package var path: String {
      switch self {
      case .book(let path), .appleDouble(let path), .sidecar(let path), .thumbnail(let path),
        .thumbnailAppleDouble(let path):
        path
      }
    }
  }

  /// Paths relative to the Kindle's root, in the order they are held.
  package let parts: [Part]
  /// Folders under documents/ to remove once empty, deepest first, after the delete is final.
  package let emptyFolders: [String]

  private static let kindleFolders: Set<String> = ["Downloads", "Downloads/Items01"]

  /// Nil when `book` isn't in `listing` or its path isn't a book under documents/ Sendle may
  /// delete. `siblings` are the lowercased file names in the book's folder, the book included.
  package static func make(
    for book: KindleBook, listing: [KindleBook], siblings: Set<String>,
    thumbnailExists: (String) -> Bool
  ) -> RemovalPlan? {
    let components = book.id.relativePath.split(
      separator: "/", omittingEmptySubsequences: false)
    guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
      !book.format.isEmpty, listing.contains(where: { $0.id == book.id })
    else { return nil }

    let folders = components.dropLast().map(String.init)
    let folder = (["documents"] + folders).joined(separator: "/")
    var parts: [Part] = [
      .book("\(folder)/\(book.fileName)"), .appleDouble("\(folder)/._\(book.fileName)"),
    ]
    if !sharesSidecar(of: book, with: siblings) {
      parts.append(.sidecar("\(folder)/\(book.stem).sdr"))
    }
    parts += thumbnailParts(of: book, listing: listing, thumbnailExists: thumbnailExists)

    let emptyFolders = folders.indices.reversed().compactMap { depth -> String? in
      let path = folders[...depth].joined(separator: "/")
      return kindleFolders.contains(path) ? nil : "documents/\(path)"
    }
    return RemovalPlan(parts: parts, emptyFolders: emptyFolders)
  }

  private static func sharesSidecar(of book: KindleBook, with siblings: Set<String>) -> Bool {
    let own = book.fileName.lowercased()
    let stem = book.stem.lowercased()
    return siblings.contains { name in
      guard name != own, let dot = name.lastIndex(of: "."), dot != name.startIndex else {
        return false
      }
      return name[..<dot] == stem
        && KindleBookReader.formats.contains(String(name[name.index(after: dot)...]))
    }
  }

  private static func thumbnailParts(
    of book: KindleBook, listing: [KindleBook], thumbnailExists: (String) -> Bool
  ) -> [Part] {
    guard let asin = book.asin, let type = book.documentType,
      !listing.contains(where: { $0.id != book.id && $0.asin == asin && $0.documentType == type })
    else { return [] }
    let name = ThumbnailName.of(asin: asin, type: type)
    let path = "\(ThumbnailName.folder)/\(name)"
    guard thumbnailExists(path) else { return [] }
    return [.thumbnail(path), .thumbnailAppleDouble("\(ThumbnailName.folder)/._\(name)")]
  }
}
