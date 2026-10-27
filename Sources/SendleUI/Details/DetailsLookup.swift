import Foundation
import SendleDomain

/// How the details sheet looks a book up online, without seeing a store or a source.
package struct DetailsLookup: Sendable {
  /// The enabled sources, in order.
  package let sources: [LookupSource]
  /// Refreshing skips the answers kept from earlier lookups. Ending the stream stops the lookup.
  package let search: @Sendable (LookupQuery, _ refreshing: Bool) -> AsyncStream<LookupProgress>
  package let refine: @Sendable (FoundEdition) async -> FoundEdition
  package let image: @Sendable (URL, LookupSource) async -> Data?

  package init(
    sources: [LookupSource],
    search: @escaping @Sendable (LookupQuery, _ refreshing: Bool) -> AsyncStream<LookupProgress>,
    refine: @escaping @Sendable (FoundEdition) async -> FoundEdition,
    image: @escaping @Sendable (URL, LookupSource) async -> Data?
  ) {
    self.sources = sources
    self.search = search
    self.refine = refine
    self.image = image
  }
}

/// What the banner at the top of the sheet says about a lookup.
package enum LookupBanner: Equatable, Sendable {
  case searching(LookupMethod)
  case found(LookupSource, differences: Int)
  case allAgree([LookupSource])
  case editions(LookupSource, hadISBN: Bool)
  case nothingFound
  case offline
  case unreachable([LookupSource])
  /// Some sources failed and the rest didn't find the book.
  case partlyUnreachable(failed: [LookupSource], notFound: [LookupSource])

  /// The view adds the difference count and the source's ▾ itself.
  package var text: String { text(onEditionList: false) }

  /// On the edition list, which has Retry in place of 🌐, being offline points at Retry.
  package func text(onEditionList: Bool) -> String {
    switch self {
    case .searching(.isbn): "Looking up by ISBN…"
    case .searching(.titleAndAuthor): "Looking up by title and author…"
    case .found(let source, _): "Found on \(source.name)"
    case .allAgree(let sources):
      Self.names(sources, or: "and") + (sources.count == 1 ? " agrees" : " agree")
        + " with everything here."
    case .editions(let source, let hadISBN):
      (hadISBN ? "No source knows this ISBN" : "No ISBN")
        + ", so searched \(source.name) by title and author"
    case .nothingFound: "No source knows this book."
    case .offline:
      onEditionList
        ? "You're offline. Connect, then Retry." : "You're offline. Connect and try 🌐 again."
    case .unreachable(let sources):
      "Couldn't reach \(Self.names(sources, or: "or")). Try again later."
    case .partlyUnreachable(let failed, let notFound):
      "Couldn't reach \(Self.names(failed, or: "or")), and \(Self.names(notFound, or: "and"))"
        + " didn't find this book. Try again later."
    }
  }

  /// "A", "A and B", "A, B and C".
  private static func names(_ sources: [LookupSource], or last: String) -> String {
    let names = sources.map(\.name)
    guard let final = names.last, names.count > 1 else { return names.first ?? "" }
    return "\(names.dropLast().joined(separator: ", ")) \(last) \(final)"
  }
}

/// What the bubble under a field says about the shown edition's value, as the bubble shows it: a
/// language by name, and an empty value as "—".
package enum FoundValue: Equatable, Sendable {
  case differs(String)
  case matches
  /// Use filled the field; Undo puts back what it held.
  case used(was: String)
}

/// The shown edition's cover, offered in place of the book's.
package struct FoundCover: Equatable, Sendable {
  package let url: URL
  package let file: CoverImageFile

  /// "1600 × 2400".
  package var sizeText: String { "\(file.pixelWidth) × \(file.pixelHeight)" }
}

/// One edition in the list the user picks theirs from.
package struct EditionRow: Identifiable, Equatable, Sendable {
  /// The edition's place in the list.
  package let id: Int
  package let edition: FoundEdition
  package let title: String
  /// Author, year and language; for Apple Books, which has no dates, author and "Apple Books ebook".
  package let detail: String
  /// Publisher and ISBN, only to tell editions apart; never for Apple Books.
  package let identifiers: String?
  /// The edition's page, for Google Books, whose terms want each result to link to it.
  package let link: URL?

  package init(id: Int, edition: FoundEdition) {
    self.id = id
    self.edition = edition
    title = edition.title ?? ""
    link = edition.source == .googleBooks ? edition.link : nil
    if edition.source == .appleBooks {
      detail = Self.joined([edition.author, "Apple Books ebook"])
      identifiers = nil
    } else {
      detail = Self.joined([
        edition.author, edition.year, edition.language.map(Formatting.languageName),
      ])
      let isbn = edition.isbn.flatMap(ISBN.normalised).map { "ISBN \($0)" }
      let identifiers = Self.joined([edition.publisher, isbn])
      self.identifiers = identifiers.isEmpty ? nil : identifiers
    }
  }

  private static func joined(_ parts: [String?]) -> String {
    parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }
}
