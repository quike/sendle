import Foundation

/// The edit sheet's fields as the user left them.
public struct BookDetailsDraft: Hashable, Sendable {
  public var title, author, year, isbn: String
  /// What the user typed into a "Sorted as" line; nil when they left it alone.
  public var sortTitle, sortName: String?
  public var language: String?
  public var cover: CoverChange
  /// "Also change the N other books by …".
  public var changesWriter: Bool

  public init(
    title: String, author: String, sortTitle: String?, sortName: String?, year: String,
    isbn: String, language: String?, cover: CoverChange, changesWriter: Bool
  ) {
    self.title = title
    self.author = author
    self.sortTitle = sortTitle
    self.sortName = sortName
    self.year = year
    self.isbn = isbn
    self.language = language
    self.cover = cover
    self.changesWriter = changesWriter
  }

  /// What the sheet opens with: what `book` shows, and its file's year and ISBN where it has no
  /// edit of its own. `otherBooks` is the count of `EditBookDetails.otherBooks(by:in:)`. The
  /// writer checkbox starts ticked when there are any, or when the book follows a writer rename,
  /// so that reverting its author also removes the rename.
  public init(showing book: Book, fileValues: Edition?, otherBooks: Int) {
    self.init(
      title: book.title, author: book.author ?? "", sortTitle: nil, sortName: nil,
      year: book.edits.year ?? fileValues?.year ?? "",
      isbn: book.edits.isbn ?? fileValues?.isbn ?? "", language: book.language, cover: .keep,
      changesWriter: otherBooks > 0 || book.edits.fields.contains(.writerName))
  }
}

public enum EditDetailsError: Error, Hashable, Sendable {
  case emptyTitle, invalidYear, invalidLanguage, unreadableImage, imageTooLarge, storage(String)

  init(_ error: MetadataEditError) {
    switch error {
    case .unreadableImage: self = .unreadableImage
    case .imageTooLarge: self = .imageTooLarge
    case .storage(let error): self = .storage(error.detail)
    }
  }
}

/// Checks the edit sheet's draft and saves it as the book's and its writer's edits.
public struct EditBookDetails: Sendable {
  private let store: any MetadataEditStore
  private let settings: (any SettingsStore)?
  private let now: @Sendable () -> Date

  public init(
    store: any MetadataEditStore, settings: (any SettingsStore)?,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.settings = settings
    self.now = now
  }

  /// Saves the fields of `draft` that differ from what the sheet opened with, and the sort lines
  /// it holds; the others keep their edits. A cleared field is reverted, as is one set back to
  /// what the book would show without its edit.
  ///
  /// `book` and `fileValues` must be the ones the draft was opened from, or untouched values may
  /// be saved as edits. `fileValues` is the book's own year and ISBN from its package, when known.
  public func save(
    _ draft: BookDetailsDraft, for book: Book, fileValues: Edition?
  ) async throws(EditDetailsError) {
    let authorSort = await settings?.load().authorSort ?? .surname
    let changes = try DraftChanges(
      draft, for: book, fileValues: fileValues, authorSort: authorSort,
      coverFolder: store.coverFolder, at: now())
    do throws(MetadataEditError) {
      try await store.update(book: book.id, cover: draft.cover) { changes.apply(to: &$0) }
    } catch {
      throw EditDetailsError(error)
    }
  }

  /// Library books whose Books author has `book`'s writer key, without `book`.
  public static func otherBooks(by book: Book, in library: [Book]) -> [Book] {
    guard let key = WriterKey(author: book.original.author) else { return [] }
    return library.filter { $0.id != book.id && WriterKey(author: $0.original.author) == key }
  }
}

/// The fields a draft changed, checked, and how saving them changes the stored edits.
private struct DraftChanges: Sendable {
  private let book: Book
  private let fileValues: Edition?
  private let changesWriter: Bool
  private let cover: CoverChange
  private let authorSort: AuthorSort
  private let coverFolder: URL
  private let date: Date
  /// Trimmed, and empty when cleared; nil when left as the sheet opened.
  private let title, author, sortTitle, sortName, year, isbn, language: String?

  init(
    _ draft: BookDetailsDraft, for book: Book, fileValues: Edition?, authorSort: AuthorSort,
    coverFolder: URL, at date: Date
  ) throws(EditDetailsError) {
    self.book = book
    self.fileValues = fileValues
    changesWriter = draft.changesWriter
    cover = draft.cover
    self.authorSort = authorSort
    self.coverFolder = coverFolder
    self.date = date

    let opened = BookDetailsDraft(showing: book, fileValues: fileValues, otherBooks: 0)
    func changed(_ field: KeyPath<BookDetailsDraft, String>) -> String? {
      let typed = draft[keyPath: field].trimmed
      return typed == opened[keyPath: field].trimmed ? nil : typed
    }
    guard !draft.title.trimmed.isEmpty else { throw .emptyTitle }
    title = changed(\.title)
    author = changed(\.author)
    sortTitle = draft.sortTitle?.trimmed
    sortName = draft.sortName?.trimmed
    isbn = changed(\.isbn)

    let year = changed(\.year)
    if let year, Self.edit(year, standard: fileValues?.year) != nil, !Self.isYear(year) {
      throw .invalidYear
    }
    self.year = year
    var language = changed(\.languageText)
    if let typed = language {
      language = try Self.languageTag(typed, standard: book.original.language)
    }
    self.language = language
  }

  func apply(to edits: inout MetadataEdits) {
    let before = edits.books[book.id] ?? BookEdit()
    var own = before
    if let title { own.title = Self.edit(title, standard: book.original.title) }
    if let year { own.year = Self.edit(year, standard: fileValues?.year) }
    if let isbn { own.isbn = Self.edit(isbn, standard: fileValues?.isbn) }
    if let language { own.language = Self.edit(language, standard: book.original.language) }
    if let author { rename(to: author, own: &own, in: &edits) }
    if let sortTitle {
      own.sortTitle = nil
      let standard = shown(edits, own: own)
      own.sortTitle = Self.edit(sortTitle, standard: standard.sortTitle ?? standard.title)
    }
    if reachesTheFile(before, own) { own.changedAt = date }
    if own != before { edits.books[book.id] = own }
    if authorSort == .surname, let sortName { setSortName(sortName, in: &edits) }
  }

  /// A writer-wide rename goes under the key of the author Books has, and the book follows it.
  /// Cleared for this book alone, the author is Books', which overrides a writer's rename.
  /// Cleared on a book that neither shows nor hides the writer's rename, it leaves the rename.
  private func rename(to author: String, own: inout BookEdit, in edits: inout MetadataEdits) {
    own.author = nil
    let reachesWriter =
      !author.isEmpty || book.edits.fields.contains(.writerName)
      || book.edits.overridesWriterRename
    guard changesWriter, reachesWriter, let key = WriterKey(author: book.original.author) else {
      let typed = author.isEmpty ? book.original.author?.trimmed ?? "" : author
      own.author = Self.edit(typed, standard: shown(edits, own: own).author)
      return
    }
    var writer = edits.writers[key] ?? WriterEdit()
    let name = Self.edit(author, standard: book.original.author)
    guard writer.name != name else { return }
    writer.name = name
    writer.nameChangedAt = date
    edits.writers[key] = writer
  }

  /// Stored under the key of the author the book shows once saved.
  private func setSortName(_ sortName: String, in edits: inout MetadataEdits) {
    guard let key = WriterKey(author: shown(edits).author) else { return }
    var writer = edits.writers[key] ?? WriterEdit()
    var without = edits
    without.writers[key]?.sortName = nil
    let standard = shown(without)
    let name = Self.edit(sortName, standard: standard.sortAuthor ?? standard.author)
    guard writer.sortName != name else { return }
    writer.sortName = name
    writer.sortNameChangedAt = date
    edits.writers[key] = writer
  }

  private func reachesTheFile(_ before: BookEdit, _ after: BookEdit) -> Bool {
    let written: [KeyPath<BookEdit, String?>] = [\.title, \.author, \.year, \.isbn, \.language]
    let coverChanges =
      switch cover {
      case .keep: false
      case .replace: true
      case .revert: before.cover != nil
      }
    return coverChanges || written.contains { before[keyPath: $0] != after[keyPath: $0] }
  }

  /// The book as `edits` show it, with `own` as its own entry when given.
  private func shown(_ edits: MetadataEdits, own: BookEdit? = nil) -> Book {
    var edits = edits
    if let own { edits.books[book.id] = own }
    return edits.apply(to: book, authorSort: authorSort, coverFolder: coverFolder)
  }

  /// The edit a changed field leaves: none when cleared or set back to `standard`.
  private static func edit(_ typed: String, standard: String?) -> String? {
    typed.isEmpty || typed == standard?.trimmed ? nil : typed
  }

  private static func isYear(_ text: String) -> Bool {
    text.count == 4 && text.allSatisfy { $0.isASCII && $0.isNumber }
  }

  /// `typed` as a BCP 47 tag with "_" read as "-", or empty when it names the book's own
  /// language, which is kept even when it isn't a tag.
  private static func languageTag(
    _ typed: String, standard: String?
  ) throws(EditDetailsError) -> String {
    let tag = typed.replacingOccurrences(of: "_", with: "-")
    let own = standard?.trimmed.replacingOccurrences(of: "_", with: "-") ?? ""
    if tag.isEmpty || tag.caseInsensitiveCompare(own) == .orderedSame { return "" }
    guard tag.wholeMatch(of: #/[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/#) != nil else {
      throw .invalidLanguage
    }
    return tag
  }
}

extension BookDetailsDraft {
  fileprivate var languageText: String { language ?? "" }
}

extension String {
  fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
