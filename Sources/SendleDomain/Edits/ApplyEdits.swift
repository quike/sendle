import Foundation

extension MetadataEdits {
  /// The book with its edits applied over what Books holds for it (`book.original`), so applying
  /// again to an edited book gives the same result.
  public func apply(to book: Book, authorSort: AuthorSort, coverFolder: URL) -> Book {
    let original = book.original
    let own = books[book.id] ?? BookEdit()
    var fields = own.editedFields
    var changes = [own.changedAt]

    var author = own.author ?? original.author
    if own.author == nil, let rename = writer(for: original.author), let name = rename.name {
      author = name
      fields.insert(.writerName)
      changes.append(rename.nameChangedAt)
    }
    let authorEdited = own.author != nil || fields.contains(.writerName)

    var writerSortName: String?
    if authorSort == .surname, let writer = writer(for: author), let name = writer.sortName {
      writerSortName = name
      fields.insert(.writerSortName)
      changes.append(writer.sortNameChangedAt)
    }

    let title = own.title ?? original.title
    let language = own.language ?? original.language
    let sortTitle =
      own.sortTitle ?? SortNames.title(title, language: language)
      ?? (own.title == nil ? original.sortTitle : nil)
    let sortAuthor =
      switch authorSort {
      case .firstName: author
      case .surname:
        writerSortName ?? (authorEdited ? author.map(SortNames.author) : original.sortAuthor)
      }

    return Book(
      id: book.id, title: title, author: author, language: language, format: book.format,
      fileURL: book.fileURL, sizeBytes: book.sizeBytes, addedAt: book.addedAt,
      isStorePurchase: book.isStorePurchase, availability: book.availability,
      sortTitle: sortTitle, sortAuthor: sortAuthor, original: original,
      edits: AppliedEdits(
        fields: fields, year: own.year, isbn: own.isbn,
        cover: own.cover.map { coverFolder.appending(path: $0, directoryHint: .notDirectory) },
        changedAt: changes.compactMap { $0 }.max()))
  }

  private func writer(for author: String?) -> WriterEdit? {
    WriterKey(author: author).flatMap { writers[$0] }
  }
}

extension BookEdit {
  fileprivate var editedFields: Set<EditedField> {
    let edited: [(EditedField, String?)] = [
      (.title, title), (.author, author), (.sortTitle, sortTitle), (.year, year),
      (.isbn, isbn), (.language, language), (.cover, cover),
    ]
    return Set(edited.filter { $0.1 != nil }.map(\.0))
  }
}
