import Foundation

/// Stable identifier of a book in the Books library (its asset ID).
public struct BookID: RawRepresentable, Hashable, Sendable, Codable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

extension BookID: CodingKeyRepresentable {}

/// Formats Books can hold that Sendle knows how to send.
public enum BookFormat: String, Sendable, Codable, CaseIterable {
  case epub
  case pdf

  public var fileFormat: FileFormat {
    switch self {
    case .epub: .epub
    case .pdf: .pdf
    }
  }
}

public enum Availability: String, Sendable, Codable, CaseIterable {
  case ready
  case protected
  case inCloudOnly
  case missing
}

public struct Book: Sendable, Hashable, Identifiable {
  public let id: BookID
  public let title: String
  public let author: String?
  public let language: String?
  public let format: BookFormat
  public let fileURL: URL
  public let sizeBytes: Int64?
  public let addedAt: Date
  public let isStorePurchase: Bool
  public var availability: Availability
  /// The sort keys the library orders by, such as "Hobbit, The" or "Tolkien, J. R. R.", when the
  /// book has them.
  public let sortTitle: String?
  public let sortAuthor: String?
  /// What Books holds for the details above, which the user's edits may have replaced.
  public let original: BooksDetails
  public let edits: AppliedEdits

  public init(
    id: BookID,
    title: String,
    author: String?,
    language: String? = nil,
    format: BookFormat,
    fileURL: URL,
    sizeBytes: Int64?,
    addedAt: Date,
    isStorePurchase: Bool = false,
    availability: Availability = .ready,
    sortTitle: String? = nil,
    sortAuthor: String? = nil
  ) {
    self.init(
      id: id, title: title, author: author, language: language, format: format,
      fileURL: fileURL, sizeBytes: sizeBytes, addedAt: addedAt,
      isStorePurchase: isStorePurchase, availability: availability,
      sortTitle: sortTitle, sortAuthor: sortAuthor,
      original: BooksDetails(
        title: title, author: author, language: language,
        sortTitle: sortTitle, sortAuthor: sortAuthor),
      edits: .none)
  }

  package init(
    id: BookID,
    title: String,
    author: String?,
    language: String?,
    format: BookFormat,
    fileURL: URL,
    sizeBytes: Int64?,
    addedAt: Date,
    isStorePurchase: Bool,
    availability: Availability,
    sortTitle: String?,
    sortAuthor: String?,
    original: BooksDetails,
    edits: AppliedEdits
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.language = language
    self.format = format
    self.fileURL = fileURL
    self.sizeBytes = sizeBytes
    self.addedAt = addedAt
    self.isStorePurchase = isStorePurchase
    self.availability = availability
    self.sortTitle = sortTitle
    self.sortAuthor = sortAuthor
    self.original = original
    self.edits = edits
  }

  /// The book as Books has it, with none of the user's edits.
  public var unedited: Book {
    Book(
      id: id, title: original.title, author: original.author, language: original.language,
      format: format, fileURL: fileURL, sizeBytes: sizeBytes, addedAt: addedAt,
      isStorePurchase: isStorePurchase, availability: availability,
      sortTitle: original.sortTitle, sortAuthor: original.sortAuthor)
  }
}
