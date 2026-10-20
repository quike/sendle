import Foundation

/// A detail a send writes into a book's package document.
public enum PackageDetail: String, Hashable, Sendable, CaseIterable {
  case title, author, language, year, isbn, cover
}

/// What a send writes into a book's package document. A nil value leaves the book's own.
public struct PackageDetails: Hashable, Sendable {
  public var title: String?
  public var creator: String?
  public var language: String?
  public var year: String?
  /// 13 digits; set only for a valid edited ISBN.
  public var isbn: String?
  public var cover: URL?
  /// The edited ISBN isn't valid, so it isn't written.
  public var skipsISBN: Bool

  public init(
    title: String? = nil,
    creator: String? = nil,
    language: String? = nil,
    year: String? = nil,
    isbn: String? = nil,
    cover: URL? = nil,
    skipsISBN: Bool = false
  ) {
    self.title = title
    self.creator = creator
    self.language = language
    self.year = year
    self.isbn = isbn
    self.cover = cover
    self.skipsISBN = skipsISBN
  }

  /// Nothing to write.
  public var isEmpty: Bool {
    title == nil && creator == nil && language == nil && year == nil && isbn == nil
      && cover == nil
  }

  /// What sending `book` writes, with the author in the form `authorSort` files it under.
  public static func `for`(_ book: Book, authorSort: AuthorSort) -> PackageDetails {
    let edits = book.edits
    let isbn = edits.isbn.flatMap(ISBN.normalised)
    return PackageDetails(
      title: edits.fields.contains(.title) ? book.title : nil,
      creator: creator(of: book, authorSort: authorSort),
      language: edits.fields.contains(.language) ? book.language : nil,
      year: edits.year,
      isbn: isbn,
      cover: edits.cover,
      skipsISBN: edits.isbn != nil && isbn == nil)
  }

  /// The sort form for a single writer under Surname when it is valid, else the shown author
  /// once it is edited; nil leaves the book's creators alone.
  private static func creator(of book: Book, authorSort: AuthorSort) -> String? {
    guard let author = book.author else { return nil }
    if authorSort == .surname, SortNames.isSingleWriter(author), let sort = book.sortAuthor,
      SortNames.isSortForm(sort)
    {
      return sort
    }
    let edited = !book.edits.fields.isDisjoint(with: [.author, .writerName])
    return edited ? author : nil
  }
}
