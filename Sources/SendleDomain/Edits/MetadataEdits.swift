import Foundation

/// Identifies a writer by their name with case, accents, punctuation and word order folded away.
public struct WriterKey: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init?(author: String?) {
    guard let author else { return nil }
    let key = NameKey.authors([author]).sorted().joined(separator: "|")
    guard !key.isEmpty else { return nil }
    self.rawValue = key
  }
}

/// The details a user changed on one book. A nil field is not edited.
public struct BookEdit: Hashable, Sendable, Codable {
  public var title: String?
  public var author: String?
  public var sortTitle: String?
  public var year: String?
  public var isbn: String?
  public var language: String?
  /// File name of the image in the store's cover folder.
  public var cover: String?
  public var changedAt: Date?

  public init(
    title: String? = nil,
    author: String? = nil,
    sortTitle: String? = nil,
    year: String? = nil,
    isbn: String? = nil,
    language: String? = nil,
    cover: String? = nil,
    changedAt: Date? = nil
  ) {
    self.title = title
    self.author = author
    self.sortTitle = sortTitle
    self.year = year
    self.isbn = isbn
    self.language = language
    self.cover = cover
    self.changedAt = changedAt
  }

  public var hasEdits: Bool {
    [title, author, sortTitle, year, isbn, language, cover].contains { $0 != nil }
  }
}

/// A rename or a sort name that applies to every book shown with one writer.
public struct WriterEdit: Hashable, Sendable, Codable {
  public var name: String?
  public var sortName: String?
  public var nameChangedAt: Date?
  public var sortNameChangedAt: Date?

  public init(
    name: String? = nil,
    sortName: String? = nil,
    nameChangedAt: Date? = nil,
    sortNameChangedAt: Date? = nil
  ) {
    self.name = name
    self.sortName = sortName
    self.nameChangedAt = nameChangedAt
    self.sortNameChangedAt = sortNameChangedAt
  }

  public var isEmpty: Bool { name == nil && sortName == nil }
}

public struct MetadataEdits: Hashable, Sendable, Codable {
  public var books: [BookID: BookEdit]
  public var writers: [WriterKey: WriterEdit]

  public init(books: [BookID: BookEdit] = [:], writers: [WriterKey: WriterEdit] = [:]) {
    self.books = books
    self.writers = writers
  }

  public static let none = MetadataEdits()
}

public enum EditedField: String, Hashable, Sendable, CaseIterable {
  case title
  case author
  case sortTitle
  case year
  case isbn
  case language
  case cover
  case writerName
  case writerSortName
}

/// What Books itself holds for a book, kept beside the values shown.
public struct BooksDetails: Hashable, Sendable {
  public let title: String
  public let author: String?
  public let language: String?
  public let sortTitle: String?
  public let sortAuthor: String?

  public init(
    title: String,
    author: String? = nil,
    language: String? = nil,
    sortTitle: String? = nil,
    sortAuthor: String? = nil
  ) {
    self.title = title
    self.author = author
    self.language = language
    self.sortTitle = sortTitle
    self.sortAuthor = sortAuthor
  }
}

/// The edits that reach one book, once the book's own and its writer's are resolved.
public struct AppliedEdits: Hashable, Sendable {
  public var fields: Set<EditedField>
  public var year: String?
  public var isbn: String?
  public var cover: URL?
  /// The latest change to what Sendle writes into the file.
  public var changedAt: Date?
  /// The book's own author hides a rename of its writer.
  public var overridesWriterRename: Bool

  public init(
    fields: Set<EditedField> = [],
    year: String? = nil,
    isbn: String? = nil,
    cover: URL? = nil,
    changedAt: Date? = nil,
    overridesWriterRename: Bool = false
  ) {
    self.fields = fields
    self.year = year
    self.isbn = isbn
    self.cover = cover
    self.changedAt = changedAt
    self.overridesWriterRename = overridesWriterRename
  }

  public var isEdited: Bool { !fields.isEmpty }

  public static let none = AppliedEdits()
}
