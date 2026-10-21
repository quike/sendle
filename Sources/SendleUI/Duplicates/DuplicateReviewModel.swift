import Foundation
import Observation
import SendleDomain

package enum DuplicateChoice: Hashable, Sendable {
  case skip
  case keepBoth
  case replace

  package var title: String {
    switch self {
    case .skip: "Skip"
    case .keepBoth: "Keep both"
    case .replace: "Replace"
    }
  }
}

/// What Replace would do to the copy already on the Kindle.
package enum ReplaceKind: Hashable, Sendable {
  /// The new copy goes under the file name of the old one.
  case inPlace
  /// The old copy has another name, so it would be deleted.
  case removesOther
  case unavailable
}

/// A book about to be sent that a Kindle already has.
package struct DuplicateCase: Identifiable, Hashable, Sendable {
  package let book: Book
  package let edition: Edition?
  package let match: KindleMatch
  package let replace: ReplaceKind

  package var id: BookID { book.id }

  package init(book: Book, edition: Edition?, match: KindleMatch, replace: ReplaceKind) {
    self.book = book
    self.edition = edition
    self.match = match
    self.replace = replace
  }
}

/// What checking a Kindle for the books about to be sent found.
package enum DuplicateCheck: Hashable, Sendable {
  /// The books the Kindle already has, if any, and the listing they were found in.
  case checked([DuplicateCase], in: KindleListing)
  case unreadable(KindleListingError)
  /// The Kindle changed before the check finished, so it says nothing about the one sent to.
  case interrupted
}

/// One line of the comparison: the same fact on each side.
package struct ComparisonRow: Hashable, Sendable {
  package let label: String
  package let library: String
  package let kindle: String
  /// The two sides disagree in a way that could make them different books.
  package let differs: Bool

  package init(label: String, library: String, kindle: String, differs: Bool) {
    self.label = label
    self.library = library
    self.kindle = kindle
    self.differs = differs
  }
}

/// Walks the duplicates of a USB send one by one, recording what to do with each.
@Observable @MainActor
package final class DuplicateReviewModel {
  package let cases: [DuplicateCase]
  package private(set) var index = 0
  /// Applies each choice to the other undecided duplicates of the same confidence.
  package var appliesToRest = false
  package private(set) var decisions: [BookID: DuplicateChoice] = [:]

  private let zone: TimeZone

  package init(cases: [DuplicateCase], zone: TimeZone = .current) {
    precondition(!cases.isEmpty, "a review needs a duplicate to show")
    self.cases = cases
    self.zone = zone
  }

  package var isFinished: Bool { index >= cases.count }

  package var current: DuplicateCase { cases[min(index, cases.count - 1)] }

  package var counter: String { "\(min(index + 1, cases.count)) of \(cases.count)" }

  package var badge: String {
    switch current.match.confidence {
    case .sure: "Same edition"
    case .maybe:
      current.match.reason == .titleOnly
        ? "Same title · maybe another edition" : "Same title and author · maybe another edition"
    }
  }

  package var choices: [DuplicateChoice] {
    current.replace == .unavailable ? [.skip, .keepBoth] : [.skip, .keepBoth, .replace]
  }

  package var defaultChoice: DuplicateChoice {
    current.match.confidence == .sure && current.replace != .unavailable ? .replace : .skip
  }

  /// Another undecided duplicate of the same confidence is left for the choice to reach.
  package var canApplyToRest: Bool {
    cases.contains {
      $0.id != current.id && decisions[$0.id] == nil
        && $0.match.confidence == current.match.confidence
    }
  }

  package var note: String {
    switch current.replace {
    case .inPlace:
      "Replace keeps your reading position: the new copy goes under the same file name."
    case .removesOther:
      current.match.book.isKindleDownload
        ? "Replace removes only the download; the book stays in your Amazon library."
        : "Replace removes this copy with its reading position, bookmarks and highlights."
    case .unavailable:
      current.match.book.source == .sendle
        ? "This copy has another name on the Kindle, so Sendle won't replace it. "
          + "Skip it, or keep both."
        : "Sendle didn't put this copy on the Kindle, so it won't replace it. "
          + "Skip it, or keep both."
    }
  }

  package var rows: [ComparisonRow] {
    let book = current.book
    let edition = current.edition
    let kindle = current.match.book
    let delivered = book.format == .epub ? FileFormat.azw3 : .pdf
    let bothPDFs = book.format == .pdf && kindle.format == "pdf"
    return [
      ComparisonRow(
        label: "Title", library: book.title, kindle: kindle.title,
        differs: NameKey.title(book.title) != NameKey.title(kindle.title)),
      ComparisonRow(
        label: "Author", library: Self.text(book.author),
        kindle: Self.text(kindle.authors.map(SortNames.displayForm).joined(separator: ", ")),
        differs: Self.authorsDiffer(book.author, kindle.authors)),
      ComparisonRow(
        label: "Publisher", library: Self.text(edition?.publisher),
        kindle: Self.text(kindle.publisher),
        differs: Self.publishersDiffer(edition?.publisher, kindle.publisher)),
      ComparisonRow(
        label: "ISBN", library: Self.text(edition?.isbn), kindle: Self.text(kindle.isbn),
        differs: Self.isbnsDiffer(edition?.isbn, kindle.isbn)),
      ComparisonRow(
        label: "Format",
        library: book.format == .epub ? "EPUB → AZW3" : "PDF",
        kindle: kindle.format.uppercased(),
        differs: delivered.fileExtension != kindle.format),
      ComparisonRow(
        label: "Size", library: book.sizeBytes.map { Formatting.size($0) } ?? "—",
        kindle: Formatting.size(kindle.byteCount),
        differs: bothPDFs && book.sizeBytes != kindle.byteCount),
      ComparisonRow(
        label: "Date", library: "Added \(Formatting.day(book.addedAt, in: zone))",
        kindle: "Copied \(Formatting.day(kindle.modified, in: zone))", differs: false),
      ComparisonRow(
        label: "Source", library: "Books library", kindle: kindle.source.label, differs: false),
    ]
  }

  // MARK: Choosing

  /// A choice the duplicate doesn't offer is ignored.
  package func choose(_ choice: DuplicateChoice) {
    guard !isFinished, choices.contains(choice) else { return }
    let confidence = current.match.confidence
    decisions[current.id] = choice
    if appliesToRest {
      for other in cases
      where decisions[other.id] == nil && other.match.confidence == confidence
        && (choice != .replace || other.replace != .unavailable)
      {
        decisions[other.id] = choice
      }
    }
    index = cases.firstIndex { decisions[$0.id] == nil } ?? cases.count
  }

  package func chooseDefault() {
    choose(defaultChoice)
  }

  // MARK: Private

  private static func text(_ value: String?) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return "—"
    }
    return value
  }

  private static func authorsDiffer(_ author: String?, _ kindle: [String]) -> Bool {
    let library = NameKey.authors(author.map { [$0] } ?? [])
    let device = NameKey.authors(kindle)
    return !library.isEmpty && !device.isEmpty && library.isDisjoint(with: device)
  }

  private static func publishersDiffer(_ library: String?, _ kindle: String?) -> Bool {
    let known = [library, kindle].map {
      $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    guard let first = known[0], let second = known[1], !first.isEmpty, !second.isEmpty else {
      return false
    }
    return first != second
  }

  private static func isbnsDiffer(_ library: String?, _ kindle: String?) -> Bool {
    guard let first = library.flatMap(ISBN.normalised), let second = kindle.flatMap(ISBN.normalised)
    else { return false }
    return first != second
  }
}
