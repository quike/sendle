import Foundation
import Observation
import SendleDomain

/// The edit details sheet: its fields as the user changes them, what each goes back to, and
/// saving them.
@Observable @MainActor
package final class BookDetailsViewModel {
  package enum Field: Hashable, Sendable, CaseIterable {
    case title, author, sortTitle, sortName, year, isbn, language
  }

  package enum ISBNStatus: Equatable, Sendable {
    case empty, valid, wrongCheckDigit, notAnISBN
  }

  package let book: Book
  package var title: String { didSet { forgetUse(of: .title, unlessHolding: title) } }
  package var author: String { didSet { forgetUse(of: .author, unlessHolding: author) } }
  package var year: String { didSet { forgetUse(of: .year, unlessHolding: year) } }
  package var isbn: String { didSet { forgetUse(of: .isbn, unlessHolding: isbn) } }
  package var language: String? { didSet { forgetUse(of: .language, unlessHolding: language) } }
  /// "Also change the N other books by …".
  package var changesWriter: Bool
  package var isCoverHovered = false
  /// A "Sorted as" line's Edit was clicked.
  package var isEditingSortTitle = false
  package var isEditingSortName = false
  /// "Other…" was chosen in the language pop-up.
  package private(set) var isTypingLanguage = false
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
  /// Choosing, dropping or reverting a cover forgets what Use cover replaced.
  private var cover = CoverChange.keep { didSet { coverUse = nil } }
  private let opened: BookDetailsDraft
  private let otherBooks: Int
  private let fileValues: Edition?
  private let authorSort: AuthorSort
  private let saveDraft: @MainActor (BookDetailsDraft) async throws(EditDetailsError) -> Void

  private let lookup: DetailsLookup?
  package private(set) var progress: LookupProgress?
  package private(set) var isPickingEdition = false
  /// Each row's thumbnail, by URL, once it has loaded.
  package private(set) var thumbnails: [URL: Data] = [:]
  private var query: LookupQuery?
  /// The source chosen from the ▾ menu.
  private var chosenSource: LookupSource?
  /// The edition picked from the list, refined once its source answers.
  private var pickedEdition: FoundEdition?
  /// The list opens by itself only once in a lookup.
  private var hasOpenedEditionList = false
  @ObservationIgnored private var lookupTask: Task<Void, Never>?
  /// Tells a replaced or cancelled lookup's progress from the current one's.
  @ObservationIgnored private var lookupGeneration = 0
  @ObservationIgnored private var refineTask: Task<Void, Never>?
  @ObservationIgnored private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
  /// The shown edition's cover, once fetched, when the book's cover can change.
  package private(set) var foundCover: FoundCover?
  /// What Use put in each field, and the field's value before, while the field still holds it.
  private var usedValues: [Field: (was: String?, value: String)] = [:]
  /// What Use cover replaced, while the sheet still shows the cover it put there.
  private var coverUse: (was: CoverChange, preview: Data?, url: URL)?
  /// The cover `foundCover` is, or is being fetched, for.
  @ObservationIgnored private var coverURL: URL?
  @ObservationIgnored private var coverTask: Task<Void, Never>?

  /// `save` must save the draft for this `book` and `fileValues`.
  package init(
    book: Book, library: [Book], fileValues: Edition?, authorSort: AuthorSort,
    lastSend: SendRecord?, now: Date, zone: TimeZone = .current,
    save: @escaping @MainActor (BookDetailsDraft) async throws(EditDetailsError) -> Void,
    lookup: DetailsLookup? = nil
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
    self.lookup = lookup
  }

  // MARK: Sort lines

  /// An untouched line shows what saving would leave, following the title, while the draft
  /// leaves it out so that saving it never adds or removes an edit.
  package var sortTitle: String {
    get {
      typedSortTitle
        ?? (book.edits.fields.contains(.sortTitle) ? book.sortTitle ?? "" : standardSortTitle)
    }
    set { typedSortTitle = newValue }
  }

  /// Like `sortTitle`, following the author.
  package var sortName: String {
    get { typedSortName ?? (keepsWriterSortName ? book.sortAuthor ?? "" : standardSortName) }
    set { typedSortName = newValue }
  }

  package var showsSortTitle: Bool {
    let line = sortTitle.trimmed.isEmpty ? standardSortTitle : sortTitle.trimmed
    return showsSortTitleField || line != shownTitle
  }

  /// Under First name the sort name would have no effect.
  package var showsSortName: Bool { authorSort == .surname }

  /// A "Sorted as" line shows as a field after its Edit, and while it holds an edit.
  package var showsSortTitleField: Bool { isEditingSortTitle || isEdited(.sortTitle) }
  package var showsSortNameField: Bool { isEditingSortName || isEdited(.sortName) }

  // MARK: Writer

  /// Only when ticking it changes something: a new author, a revert that may also remove the
  /// writer's rename the book shows or overrides, or "Revert all" on a book showing a writer's
  /// sort name.
  package var showsWriterCheckbox: Bool {
    guard otherBooks > 0 else { return false }
    let edits = book.edits
    let typed = author.trimmed
    let renames =
      typed.isEmpty
      ? edits.fields.contains(.writerName) || edits.overridesWriterRename
      : typed != opened.author.trimmed
    return renames || (sortNameFollowsCheckbox && edits.fields.contains(.writerSortName))
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
    if ISBN.normalised(isbn) != nil { return .valid }
    return ISBN.hasISBNDigits(isbn) ? .wrongCheckDigit : .notAnISBN
  }

  package var canSave: Bool {
    let year = year.trimmed
    return !title.trimmed.isEmpty
      && (year.isEmpty || (year.count == 4 && year.allSatisfy { $0.isASCII && $0.isNumber }))
  }

  // MARK: Languages

  /// The languages Amazon converts, by English name, then the book's and the typed tags it lacks.
  /// A tag spelled another way takes the place of its entry, so the pop-up finds it.
  package var languages: [(tag: String, name: String)] {
    var listed = Self.amazonEntries
    var others: [String] = []
    for tag in [book.original.language, book.language, language].compactMap({ $0?.trimmed })
    where !tag.isEmpty {
      let folded = Self.folded(tag)
      if let index = listed.firstIndex(where: { Self.folded($0.tag) == folded }) {
        listed[index].tag = tag
      } else if Self.isAmazonLanguage(tag) {
        listed.append((tag: tag, name: Formatting.languageName(tag)))
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

  package var languageTitle: String {
    if isTypingLanguage { return "Other…" }
    guard let tag = shownLanguage else { return "No language" }
    return languages.first { Self.folded($0.tag) == Self.folded(tag) }?.name ?? tag
  }

  package func isChosenLanguage(_ tag: String) -> Bool {
    guard !isTypingLanguage, let shown = shownLanguage else { return false }
    return Self.folded(shown) == Self.folded(tag)
  }

  package func chooseLanguage(_ tag: String) {
    language = tag
    isTypingLanguage = false
  }

  /// Shows a field for any tag, starting from the chosen one.
  package func typeOtherLanguage() {
    isTypingLanguage = true
  }

  package var typedLanguage: String {
    get { language ?? "" }
    set { language = newValue }
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
    case .language: book.original.language.map(Formatting.languageName) ?? ""
    }
  }

  package func revertHelp(_ field: Field) -> String {
    let value = placeholder(field)
    if [.sortTitle, .sortName].contains(field), !goesBackToBooks(field) {
      return "Back to the derived name: \(value)"
    }
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
    case .language:
      language = nil
      isTypingLanguage = false
    }
  }

  package var isCoverEdited: Bool {
    switch cover {
    case .keep: book.edits.fields.contains(.cover)
    case .replace: true
    case .revert: false
    }
  }

  /// `preview` is a smaller copy for the sheet to draw.
  package func setCover(_ data: Data, preview: Data? = nil) {
    guard canChangeCover else { return }
    cover = .replace(data)
    coverPreview = preview ?? data
    errorText = nil
  }

  /// A file that can't be a cover says why, as saving it would.
  package func refuseCover(_ error: EditDetailsError) {
    errorText = Self.message(for: error)
  }

  /// The book as the sheet's cover draws it: its shown title, without its stored cover once that
  /// is reverted.
  package var coverBook: Book {
    guard book.edits.cover != nil, !isCoverEdited else { return book }
    var edits = book.edits
    edits.cover = nil
    edits.fields.remove(.cover)
    return Book(
      id: book.id, title: book.title, author: book.author, language: book.language,
      format: book.format, fileURL: book.fileURL, sizeBytes: book.sizeBytes, addedAt: book.addedAt,
      isStorePurchase: book.isStorePurchase, availability: book.availability,
      sortTitle: book.sortTitle, sortAuthor: book.sortAuthor, original: book.original,
      edits: edits)
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
    isEditingSortTitle = false
    isEditingSortName = false
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
      title: title, author: author, sortTitle: typedSortTitle,
      sortName: typedSortName ?? (removesWriterSortName ? "" : nil), year: year, isbn: isbn,
      language: language, cover: cover, changesWriter: savedChangesWriter)
  }

  /// A hidden checkbox keeps the draft's default.
  private var savedChangesWriter: Bool {
    showsWriterCheckbox ? changesWriter : opened.changesWriter
  }

  private var sortNameFollowsCheckbox: Bool { revertedAll && typedSortName == nil }

  /// With no other books, the writer's sort name is effectively the book's own.
  private var removesWriterSortName: Bool {
    sortNameFollowsCheckbox && (otherBooks == 0 || savedChangesWriter)
  }

  // MARK: Lookup

  package var canLookUp: Bool { !(lookup?.sources.isEmpty ?? true) }

  /// Looks up what the fields show, in place of any lookup still running; edits stay.
  package func lookUp() {
    guard let lookup, canLookUp else { return }
    endLookup()
    let shown = shownDetails
    let query = LookupQuery(
      title: shown.title, author: shown.author, isbn: shown.isbn, language: shown.language)
    self.query = query
    progress = LookupProgress(
      sources: lookup.sources, method: query.isbn == nil ? .titleAndAuthor : .isbn)
    let generation = lookupGeneration
    let stream = lookup.search(query)
    lookupTask = Task { [weak self] in
      for await update in stream {
        guard let self, lookupGeneration == generation else { return }
        receive(update)
      }
    }
  }

  /// Ends the lookup and forgets what it found; the fields stay as they are.
  package func cancelLookup() {
    endLookup()
  }

  /// The ▾ menu's choice, else the first source in order with details.
  package var shownSource: LookupSource? {
    chosenSource ?? progress?.shownSource
  }

  /// Shows the source's edition, or its list; a source with nothing to show is ignored.
  package func show(_ source: LookupSource) {
    guard let result = progress?.result(for: source) else { return }
    switch result {
    case .asking, .notFound, .failed: return
    case .edition, .editions: break
    }
    chosenSource = source
    forgetPick()
    if case .editions = result { openEditionList() } else { isPickingEdition = false }
    fetchFoundCover()
  }

  package var editionRows: [EditionRow] {
    guard isPickingEdition, let source = shownSource,
      case .editions(let editions)? = progress?.result(for: source)
    else { return [] }
    return editions.enumerated().map { EditionRow(id: $0.offset, edition: $0.element) }
  }

  /// Shows the row's edition at once, then as its source has it under its ISBN.
  package func pick(_ row: EditionRow) {
    guard let lookup, isPickingEdition else { return }
    isPickingEdition = false
    forgetPick()
    pickedEdition = row.edition
    fetchFoundCover()
    refineTask = Task { [weak self] in
      let refined = await lookup.refine(row.edition)
      guard let self, !Task.isCancelled else { return }
      pickedEdition = refined
      fetchFoundCover()
    }
  }

  /// Skip, "None of these" and esc: ends the lookup, leaving the fields as they are.
  package func skipEditionList() {
    guard isPickingEdition else { return }
    endLookup()
  }

  package var shownEdition: FoundEdition? {
    if let pickedEdition { return pickedEdition }
    guard let source = shownSource, case .edition(let edition)? = progress?.result(for: source)
    else { return nil }
    return edition
  }

  /// The compared fields the shown edition differs in, and those Use filled; never the cover.
  package var differences: Int {
    shownEdition.map(differences(in:)) ?? 0
  }

  // MARK: Found details

  /// The bubble under a compared field, if it has one.
  package func found(_ field: Field) -> FoundValue? {
    if let used = usedValues[field] { return .used(was: Self.bubbleText(used.was, for: field)) }
    switch shownEdition.flatMap({ match(field, in: $0) }) {
    case .differs(let value)?: return .differs(Self.bubbleText(value, for: field))
    case .matches?: return .matches
    case nil: return nil
    }
  }

  /// Fills a differing field with the found value, as typing or choosing it would.
  package func use(_ field: Field) {
    guard usedValues[field] == nil, let edition = shownEdition,
      case .differs(let value)? = match(field, in: edition)
    else { return }
    let was = typedValue(field)
    fill(field, with: value)
    usedValues[field] = (was: was, value: value)
  }

  package func undo(_ field: Field) {
    guard let used = usedValues.removeValue(forKey: field) else { return }
    fill(field, with: used.was)
  }

  /// Uses every differing field, leaving the cover alone.
  package func useAll() {
    for field in Field.allCases { use(field) }
  }

  package var isFoundCoverUsed: Bool {
    guard let coverUse, let foundCover else { return false }
    return coverUse.url == foundCover.url
  }

  package func useFoundCover() {
    guard let foundCover, !isFoundCoverUsed else { return }
    let replaced = (was: cover, preview: coverPreview, url: foundCover.url)
    setCover(foundCover.file.data, preview: foundCover.file.preview)
    coverUse = replaced
  }

  package func undoFoundCover() {
    guard isFoundCoverUsed, let coverUse else { return }
    cover = coverUse.was
    coverPreview = coverUse.preview
  }

  package var banner: LookupBanner? {
    guard let progress else { return nil }
    if let edition = shownEdition {
      return agreeingSources.map { .allAgree($0) }
        ?? .found(edition.source, differences: differences)
    }
    if let source = shownSource, case .editions = progress.result(for: source) {
      return .editions(source, hadISBN: query?.isbn != nil)
    }
    guard progress.isFinished else { return .searching(progress.method) }
    let results = progress.sources.map(progress.result(for:))
    let failures = results.compactMap { result -> LookupError? in
      if case .failed(let error) = result { error } else { nil }
    }
    guard !failures.isEmpty, failures.count == results.count else { return .nothingFound }
    return failures.allSatisfy { $0 == .offline } ? .offline : .unreachable(progress.sources)
  }

  /// Every enabled source, with what it found.
  package var sourceMenu: [(source: LookupSource, status: String)] {
    guard let progress else { return [] }
    return progress.sources.map { (source: $0, status: status(of: progress.result(for: $0))) }
  }

  /// Once the lookup is over, the sources whose edition agrees with every field, when they all do
  /// and the shown edition is one of theirs.
  private var agreeingSources: [LookupSource]? {
    guard let progress, progress.isFinished, pickedEdition == nil else { return nil }
    var agreeing: [LookupSource] = []
    for source in progress.sources {
      guard case .edition(let edition) = progress.result(for: source) else { continue }
      guard differences(in: edition) == 0 else { return nil }
      agreeing.append(source)
    }
    return agreeing.isEmpty ? nil : agreeing
  }

  private func status(of result: SourceResult) -> String {
    switch result {
    case .asking: "Asking…"
    case .edition(let edition):
      switch differences(in: edition) {
      case 0: "Agrees with everything"
      case 1: "1 difference"
      case let count: "\(count) differences"
      }
    case .editions(let editions): editions.count == 1 ? "1 edition" : "\(editions.count) editions"
    case .notFound: "Didn't find this book"
    case .failed(.missingKey): "Needs your API key"
    case .failed: "Couldn't reach it"
    }
  }

  private func differences(in edition: FoundEdition) -> Int {
    Field.allCases.filter { field in
      guard usedValues[field] == nil else { return true }
      return if case .differs = match(field, in: edition) { true } else { false }
    }.count
  }

  /// How the edition's value for a field compares with what the field shows; nil when it has no
  /// value for it, or the field isn't compared. A PDF compares only its title and author.
  private func match(_ field: Field, in edition: FoundEdition) -> FieldMatch? {
    let compared: LookupField? =
      switch field {
      case .title: .title
      case .author: .author
      case .year: isPDF ? nil : .year
      case .isbn: isPDF ? nil : .isbn
      case .language: isPDF ? nil : .language
      case .sortTitle, .sortName: nil
      }
    return compared.flatMap { LookupDifferences.compare(edition, with: shownDetails)[$0] }
  }

  /// A compared field's value as typed; a language as its tag.
  private func typedValue(_ field: Field) -> String? {
    switch field {
    case .title: title
    case .author: author
    case .year: year
    case .isbn: isbn
    case .language: language
    case .sortTitle, .sortName: nil
    }
  }

  private func fill(_ field: Field, with value: String?) {
    switch field {
    case .title: title = value ?? ""
    case .author: author = value ?? ""
    case .year: year = value ?? ""
    case .isbn: isbn = value ?? ""
    case .language:
      if let value { chooseLanguage(value) } else { revert(.language) }
    case .sortTitle, .sortName: break
    }
  }

  /// Typing over a used value forgets what it replaced.
  private func forgetUse(of field: Field, unlessHolding value: String?) {
    if let used = usedValues[field], used.value != value { usedValues[field] = nil }
  }

  private static func bubbleText(_ value: String?, for field: Field) -> String {
    guard let value = value?.trimmed, !value.isEmpty else { return "—" }
    return field == .language ? Formatting.languageName(value) : value
  }

  /// What the fields show: the typed value, or what an emptied field shows in its place.
  private var shownDetails: ShownDetails {
    ShownDetails(
      title: shownTitle, author: shownAuthor,
      year: year.trimmed.isEmpty ? placeholder(.year) : year.trimmed,
      isbn: isbn.trimmed.isEmpty ? placeholder(.isbn) : isbn.trimmed, language: shownLanguage)
  }

  private func receive(_ progress: LookupProgress) {
    self.progress = progress
    fetchFoundCover()
    guard !hasOpenedEditionList, progress.method == .titleAndAuthor, let source = shownSource,
      case .editions = progress.result(for: source)
    else { return }
    openEditionList()
  }

  private func openEditionList() {
    isPickingEdition = true
    hasOpenedEditionList = true
    loadThumbnails()
  }

  /// Asks for each row's thumbnail once.
  private func loadThumbnails() {
    guard let lookup else { return }
    for edition in editionRows.map(\.edition) {
      guard let url = edition.thumbnail, thumbnailTasks[url] == nil else { continue }
      thumbnailTasks[url] = Task { [weak self] in
        let data = await lookup.image(url, edition.source)
        guard let self, !Task.isCancelled, let data else { return }
        thumbnails[url] = data
      }
    }
  }

  /// Fetches the shown edition's cover, dropping a fetch for one no longer shown.
  private func fetchFoundCover() {
    let edition = canChangeCover ? shownEdition : nil
    guard edition?.cover != coverURL else { return }
    coverTask?.cancel()
    coverURL = edition?.cover
    foundCover = nil
    guard let lookup, let edition, let url = edition.cover else { return }
    coverTask = Task { [weak self] in
      guard let data = await lookup.image(url, edition.source), !Task.isCancelled else { return }
      let file = await Task.detached { CoverImageFile.make(from: data) }.value
      guard let self, !Task.isCancelled, case .success(let file) = file else { return }
      foundCover = FoundCover(url: url, file: file)
    }
  }

  private func forgetPick() {
    refineTask?.cancel()
    refineTask = nil
    pickedEdition = nil
  }

  /// Stops the running lookup and forgets everything about it, leaving what Use filled.
  private func endLookup() {
    lookupGeneration += 1
    lookupTask?.cancel()
    lookupTask = nil
    forgetPick()
    for task in thumbnailTasks.values { task.cancel() }
    thumbnailTasks = [:]
    thumbnails = [:]
    coverTask?.cancel()
    coverTask = nil
    coverURL = nil
    foundCover = nil
    coverUse = nil
    usedValues = [:]
    progress = nil
    query = nil
    chosenSource = nil
    isPickingEdition = false
    hasOpenedEditionList = false
  }

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

  /// Whether a sort line goes back to Books' own sort value, or to its title or author when it has
  /// none, rather than to one derived from what the sheet shows.
  private func goesBackToBooks(_ field: Field) -> Bool {
    let books =
      field == .sortTitle
      ? book.original.sortTitle ?? book.original.title
      : book.original.sortAuthor ?? book.original.author ?? ""
    return placeholder(field) == books.trimmed
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

  private static let amazonEntries = amazonLanguages.map {
    (tag: $0, name: Formatting.languageName($0))
  }
  .sorted { $0.name < $1.name }

  /// Amazon's list holds primary tags, so "en-US" is on it.
  private static func isAmazonLanguage(_ tag: String) -> Bool {
    let primary = folded(tag).split(separator: "-").first.map(String.init) ?? ""
    return amazonLanguages.contains(primary)
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
