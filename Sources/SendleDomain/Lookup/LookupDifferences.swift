import Foundation

/// What the edit sheet's fields show.
public struct ShownDetails: Hashable, Sendable {
  public var title: String
  public var author: String
  public var year: String
  public var isbn: String
  public var language: String?

  public init(title: String, author: String, year: String, isbn: String, language: String?) {
    self.title = title
    self.author = author
    self.year = year
    self.isbn = isbn
    self.language = language
  }
}

public enum LookupField: Hashable, Sendable, CaseIterable {
  case title, author, year, isbn, language
}

public enum FieldMatch: Hashable, Sendable {
  /// The found value as stored: trimmed text, a four-digit year, a 13-digit ISBN or a language tag.
  case differs(String)
  case matches
}

public enum LookupDifferences {
  /// How an edition's details compare with what the sheet shows. A field the edition has no usable
  /// value for is absent.
  public static func compare(
    _ edition: FoundEdition, with shown: ShownDetails
  ) -> [LookupField: FieldMatch] {
    var result: [LookupField: FieldMatch] = [:]
    if let title = usable(edition.title) {
      result[.title] = outcome(title, same: title == trimmed(shown.title))
    }
    if let author = usable(edition.author) {
      result[.author] = outcome(author, same: author == trimmed(shown.author))
    }
    if let year = edition.year, year.count == 4, year.allSatisfy({ $0.isASCII && $0.isNumber }) {
      result[.year] = outcome(year, same: year == trimmed(shown.year))
    }
    if let isbn = edition.isbn.flatMap(ISBN.normalised) {
      result[.isbn] = outcome(isbn, same: ISBN.normalised(shown.isbn) == isbn)
    }
    if let language = usable(edition.language), let primary = LanguageTag.primary(language) {
      let shownPrimary = shown.language.flatMap(LanguageTag.primary)
      result[.language] = outcome(language, same: shownPrimary == primary)
    }
    return result
  }

  private static func outcome(_ found: String, same: Bool) -> FieldMatch {
    same ? .matches : .differs(found)
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func usable(_ text: String?) -> String? {
    guard let text = text.map(trimmed), !text.isEmpty else { return nil }
    return text
  }
}
