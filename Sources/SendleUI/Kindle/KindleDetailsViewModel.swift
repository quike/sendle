import Foundation
import SendleDomain

/// What the read-only sheet shows about one Kindle book.
package struct KindleDetailsViewModel: Hashable, Sendable {
  /// The library book whose strongest match is this Kindle book.
  package struct LibraryLink: Hashable, Sendable {
    package let id: BookID
    package let title: String
    package let isSure: Bool
    package let canEdit: Bool

    package init(id: BookID, title: String, isSure: Bool, canEdit: Bool) {
      self.id = id
      self.title = title
      self.isSure = isSure
      self.canEdit = canEdit
    }
  }

  package let item: KindleItemViewModel
  /// The format, the size and file date, and where the book came from.
  package let facts: [String]
  package let title: String
  package let author: String?
  package let year: String?
  package let isbn: String?
  package let language: String?
  package let publisher: String?
  package let file: String
  /// "SNOQSFAIKY · Book".
  package let asin: String?
  package let note: String?
  package let library: LibraryLink?

  package var libraryLine: String? {
    library.map { "\($0.isSure ? "In your library" : "Maybe in your library") as \"\($0.title)\"" }
  }

  package init(book: KindleBook, library: LibraryLink?, zone: TimeZone = .current) {
    let item = KindleItemViewModel(book: book, inLibrary: nil)
    self.item = item
    facts = [
      item.badge,
      "\(Formatting.size(book.byteCount)) · copied \(Formatting.day(book.modified, in: zone))",
      book.source.label,
    ]
    title = book.title
    author = book.authors.isEmpty ? nil : item.byline
    year = Self.text(book.year)
    isbn = Self.text(book.isbn)
    language = Self.text(book.language).map(Formatting.languageName)
    publisher = Self.text(book.publisher)
    file = "documents/\(book.id.relativePath)"
    asin = Self.asin(of: book)
    note = Self.note(for: book)
    self.library = library
  }

  private static func text(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func asin(of book: KindleBook) -> String? {
    let type = text(book.documentType).map {
      switch $0 {
      case "EBOK": "Book"
      case "PDOC": "Personal document"
      default: $0
      }
    }
    let parts = [text(book.asin), type].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private static func note(for book: KindleBook) -> String? {
    switch book.format {
    case "kfx": "Sendle can't read inside KFX files, so these details come from the file name."
    case "txt": "A text file holds no details, so these come from its file name."
    default: book.isProtected ? "Protected by DRM." : nil
    }
  }
}
