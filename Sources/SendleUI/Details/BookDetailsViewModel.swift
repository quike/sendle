import Foundation
import Observation
import SendleDomain

/// The edit details sheet: its fields as the user changes them, what each goes back to, and
/// saving them (spec §3.2).
@Observable @MainActor
package final class BookDetailsViewModel {
  package enum Field: Hashable, Sendable, CaseIterable {
    case title, author, sortTitle, sortName, year, isbn, language
  }

  package enum ISBNStatus: Equatable, Sendable {
    case empty, valid, invalid
  }

  package let book: Book
  package var title: String
  package var author: String
  package var year: String
  package var isbn: String
  package var language: String?
  /// "Also change the N other books by …".
  package var changesWriter: Bool
  package var isCoverHovered = false
  /// A replacement chosen or dropped.
  package private(set) var coverPreview: Data?
  package private(set) var errorText: String?
  /// The format, the size and date added, and the last send.
  package let facts: [String]

  /// What the user typed into a "Sorted as" line; nil until they do.
  private var typedSortTitle: String?
  private var typedSortName: String?
  /// Set by "Revert all", which leaves the writer's sort name to the checkbox.
  private var revertedAll = false
  private var cover = CoverChange.keep
  private let opened: BookDetailsDraft
  private let otherBooks: Int
  private let fileValues: Edition?
  private let authorSort: AuthorSort
  private let saveDraft: @MainActor (BookDetailsDraft) async throws(EditDetailsError) -> Void

  /// `save` must save the draft for this `book` and `fileValues`.
  package init(
    book: Book, library: [Book], fileValues: Edition?, authorSort: AuthorSort,
    lastSend: SendRecord?, now: Date, zone: TimeZone = .current,
    save: @escaping @MainActor (BookDetailsDraft) async throws(EditDetailsError) -> Void
  ) {
    let otherBooks = EditBookDetails.otherBooks(by: book, in: library).count
    let opened = BookDetailsDraft(showing: book, fileValues: fileValues, otherBooks: otherBooks)
    self.book = book
    title = opened.title
    author = opened.author
    year = opened.year
    isbn = opened.isbn
    language = opened.language
    changesWriter = opened.changesWriter
    facts = Self.facts(of: book, lastSend: lastSend, now: now, zone: zone)
    self.opened = opened
    self.otherBooks = otherBooks
    self.fileValues = fileValues
    self.authorSort = authorSort
    saveDraft = save
  }

  // MARK: Sort lines

  /// An untouched line shows what saving would leave, following the title, while the draft keeps
  /// the opening value so that saving it never adds or removes an edit.
  package var sortTitle: String {
    get {
      typedSortTitle
        ?? (book.edits.fields.contains(.sortTitle) ? opened.sortTitle : standardSortTitle)
    }
    set { typedSortTitle = newValue }
  }

  /// Like `sortTitle`, following the author.
  package var sortName: String {
    get { typedSortName ?? (keepsWriterSortName ? opened.sortName : standardSortName) }
    set { typedSortName = newValue }
  }

  package var showsSortTitle: Bool {
    let line = sortTitle.trimmed.isEmpty ? standardSortTitle : sortTitle.trimmed
    return isEdited(.sortTitle) || line != shownTitle
  }

  /// Under First name the sort name would have no effect.
  package var showsSortName: Bool { authorSort == .surname }

  // MARK: Writer

  /// Only when ticking it changes something: a new author, a revert that may also remove a
  /// writer's rename, or "Revert all" on a book showing a writer's sort name.
  package var showsWriterCheckbox: Bool {
    guard otherBooks > 0 else { return false }
    let fields = book.edits.fields
    let typed = author.trimmed
    let renames =
      typed.isEmpty
      ? !fields.isDisjoint(with: [.author, .writerName]) : typed != opened.author.trimmed
    return renames || (sortNameFollowsCheckbox && fields.contains(.writerSortName))
  }

  package var writerCheckboxTitle: String {
    let books = otherBooks == 1 ? "book" : "books"
    return "Also change the \(otherBooks) other \(books) by \"\(book.original.author ?? "")\""
  }

  // MARK: Checks

  package var isPDF: Bool { book.format == .pdf }

  /// A PDF's cover is its first page, and a book only in iCloud has to be downloaded first.
  package var canChangeCover: Bool { !isPDF && book.availability == .ready }

  package var isbnStatus: ISBNStatus {
    if isbn.trimmed.isEmpty { return .empty }
    return ISBN.normalised(isbn) == nil ? .invalid : .valid
  }

  package var canSave: Bool {
    let year = year.trimmed
    return !title.trimmed.isEmpty
      && (year.isEmpty || (year.count == 4 && year.allSatisfy { $0.isASCII && $0.isNumber }))
  }

  // MARK: Languages

  /// Amazon's list (spec §5.6) by English name, then the book's and the typed tags it lacks. A
  /// tag spelled another way takes the place of its entry, so the pop-up finds it.
  package var languages: [(tag: String, name: String)] {
    var listed = Self.amazonEntries
    var others: [String] = []
    for tag in [book.original.language, book.language, language].compactMap({ $0?.trimmed })
    where !tag.isEmpty {
      let folded = Self.folded(tag)
      if let index = listed.firstIndex(where: { Self.folded($0.tag) == folded }) {
        listed[index].tag = tag
      } else if Self.isAmazonLanguage(tag) {
        listed.append((tag: tag, name: Self.name(of: tag)))
      } else if let index = others.firstIndex(where: { Self.folded($0) == folded }) {
        others[index] = tag
      } else {
        others.append(tag)
      }
    }
    return listed.sorted { $0.name < $1.name } + others.map { (tag: $0, name: "Other: \($0)") }
  }

  package var languageWarning: String? {
    guard let tag = shownLanguage, !Self.isAmazonLanguage(tag) else { return nil }
    return "Amazon may not convert this language"
  }

  // MARK: Edits

  package func isEdited(_ field: Field) -> Bool {
    switch field {
    case .title: title.trimmed != book.original.title.trimmed
    case .author: Self.differs(author, from: book.original.author)
    case .year: Self.differs(year, from: fileValues?.year)
    case .isbn: Self.differs(isbn, from: fileValues?.isbn)
    case .language:
      Self.differs(Self.folded(language ?? ""), from: Self.folded(book.original.language ?? ""))
    case .sortTitle:
      typedSortTitle.map { Self.differs($0, from: standardSortTitle) }
        ?? book.edits.fields.contains(.sortTitle)
    case .sortName:
      typedSortName.map { Self.differs($0, from: standardSortName) } ?? keepsWriterSortName
    }
  }

  /// What a field goes back to, which it shows in its place once emptied; a language by name.
  package func placeholder(_ field: Field) -> String {
    switch field {
    case .title: book.original.title
    case .author: book.original.author ?? ""
    case .sortTitle: standardSortTitle
    case .sortName: standardSortName
    case .year: fileValues?.year ?? ""
    case .isbn: fileValues?.isbn ?? ""
    case .language: book.original.language.map(Self.name(of:)) ?? ""
    }
  }

  package func revertHelp(_ field: Field) -> String {
    let value = placeholder(field)
    return switch field {
    case .year: value.isEmpty ? "Back to the book's own year" : "Back to the book's: \(value)"
    case .isbn: value.isEmpty ? "Back to the book's own ISBN" : "Back to the book's: \(value)"
    case .author, .sortName: "Back to Books: \(value.isEmpty ? "no author" : value)"
    case .language: "Back to Books: \(value.isEmpty ? "no language" : value)"
    case .title, .sortTitle: "Back to Books: \(value)"
    }
  }

  /// Clears the field, which saving reads as a revert; a title can't be empty, so it gets Books'.
  package func revert(_ field: Field) {
    switch field {
    case .title: title = book.original.title
    case .author:
      author = ""
      // So that the revert also removes the writer's rename.
      if book.edits.fields.contains(.writerName) { changesWriter = true }
    case .sortTitle: typedSortTitle = ""
    case .sortName: typedSortName = ""
    case .year: year = ""
    case .isbn: isbn = ""
    case .language: language = nil
    }
  }

  package var isCoverEdited: Bool {
    switch cover {
    case .keep: book.edits.fields.contains(.cover)
    case .replace: true
    case .revert: false
    }
  }

  package func setCover(_ data: Data) {
    guard canChangeCover else { return }
    cover = .replace(data)
    coverPreview = data
  }

  package func revertCover() {
    cover = .revert
    coverPreview = nil
  }

  /// Reverts the book's own edits; its writer's rename and sort name go only with the checkbox
  /// ticked when saving, which starts ticked for them.
  package func revertAll() {
    for field in Field.allCases where field != .sortName { revert(field) }
    typedSortName = nil
    revertedAll = true
    if book.edits.fields.contains(.writerSortName) { changesWriter = true }
    revertCover()
  }

  // MARK: Saving

  /// False keeps the sheet open, with `errorText` saying why.
  package func save() async -> Bool {
    guard canSave else { return false }
    do throws(EditDetailsError) {
      try await saveDraft(draft)
    } catch {
      errorText = Self.message(for: error)
      return false
    }
    errorText = nil
    return true
  }

  private var draft: BookDetailsDraft {
    BookDetailsDraft(
      title: title, author: author, sortTitle: typedSortTitle ?? opened.sortTitle,
      sortName: typedSortName ?? (removesWriterSortName ? "" : opened.sortName), year: year,
      isbn: isbn, language: language, cover: cover, changesWriter: savedChangesWriter)
  }

  /// A hidden checkbox keeps the draft's default.
  private var savedChangesWriter: Bool {
    showsWriterCheckbox ? changesWriter : opened.changesWriter
  }

  private var sortNameFollowsCheckbox: Bool { revertedAll && typedSortName == nil }

  private var removesWriterSortName: Bool { sortNameFollowsCheckbox && savedChangesWriter }

  // MARK: Private

  private var shownTitle: String {
    title.trimmed.isEmpty ? book.original.title.trimmed : title.trimmed
  }

  private var shownAuthor: String {
    author.trimmed.isEmpty ? book.original.author?.trimmed ?? "" : author.trimmed
  }

  private var shownLanguage: String? {
    guard let language = language?.trimmed, !language.isEmpty else {
      return book.original.language
    }
    return language
  }

  /// The sort title without one of the book's own, as `MetadataEdits.apply` derives it.
  private var standardSortTitle: String {
    let title = shownTitle
    return SortNames.title(title, language: shownLanguage)
      ?? (title == book.original.title.trimmed ? book.original.sortTitle : nil) ?? title
  }

  /// The sort name without a writer's, as `MetadataEdits.apply` derives it.
  private var standardSortName: String {
    let author = shownAuthor
    guard authorSort == .surname else { return author }
    return author == book.original.author?.trimmed ?? ""
      ? book.original.sortAuthor ?? author : SortNames.author(author)
  }

  /// A writer's sort name keeps applying while the author stays the same writer.
  private var keepsWriterSortName: Bool {
    book.edits.fields.contains(.writerSortName) && !removesWriterSortName
      && WriterKey(author: shownAuthor) == WriterKey(author: opened.author)
  }

  /// Something typed that isn't what the field goes back to.
  private static func differs(_ typed: String, from standard: String?) -> Bool {
    let typed = typed.trimmed
    return !typed.isEmpty && typed != (standard?.trimmed ?? "")
  }

  private static func folded(_ tag: String) -> String {
    tag.trimmed.lowercased().replacingOccurrences(of: "_", with: "-")
  }

  private static let amazonLanguages = [
    "af", "gsw", "ar", "eu", "br", "ca", "zh", "kw", "co", "da", "nl", "stq", "en", "fi", "fr",
    "fy", "gl", "de", "gu", "hi", "is", "ga", "it", "ja", "lb", "mr", "ml", "gv", "frr", "nb",
    "nn", "pl", "pt", "oc", "rm", "sco", "gd", "es", "sv", "ta", "cy",
  ]

  private static let amazonEntries = amazonLanguages.map { (tag: $0, name: name(of: $0)) }
    .sorted { $0.name < $1.name }

  /// Amazon's list holds primary tags, so "en-US" is on it.
  private static func isAmazonLanguage(_ tag: String) -> Bool {
    let primary = folded(tag).split(separator: "-").first.map(String.init) ?? ""
    return amazonLanguages.contains(primary)
  }

  private static func name(of tag: String) -> String {
    Locale(identifier: "en").localizedString(forIdentifier: tag) ?? tag
  }

  private static func facts(
    of book: Book, lastSend: SendRecord?, now: Date, zone: TimeZone
  ) -> [String] {
    let day = Formatting.day(book.addedAt, in: zone)
    let added = book.sizeBytes.map { "\(Formatting.size($0)) · added \(day)" } ?? "Added \(day)"
    guard let lastSend, lastSend.outcome != .failed else {
      return [book.format.rawValue.uppercased(), added, "Not sent yet"]
    }
    let sent = lastSend.outcome == .sent ? "Sent" : "May have been sent"
    let way = lastSend.destination == .email ? "by email" : "over USB"
    let age = Formatting.age(of: lastSend.date, now: now)
    return [book.format.rawValue.uppercased(), added, "\(sent) \(way) · \(age)"]
  }

  private static func message(for error: EditDetailsError) -> String {
    switch error {
    case .emptyTitle: "Enter a title."
    case .invalidYear: "Enter the year as four digits, like 2017."
    case .invalidLanguage: "Enter a language tag, like es or pt-BR."
    case .unreadableImage: "Sendle can't read that image. Choose another one."
    case .imageTooLarge: "That image is over 20 MB. Choose a smaller one."
    case .storage(let detail): "Couldn't save the details: \(detail)"
    }
  }
}

extension String {
  fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
