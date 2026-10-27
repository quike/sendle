import Foundation

/// An online catalogue Sendle can look a book up in, in the order they are tried and shown.
public enum LookupSource: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
  case openLibrary
  case googleBooks
  case appleBooks

  public var name: String {
    switch self {
    case .openLibrary: "Open Library"
    case .googleBooks: "Google Books"
    case .appleBooks: "Apple Books"
    }
  }

  /// Whether the source tells when an edition was published; Apple Books does not.
  public var givesDates: Bool {
    switch self {
    case .openLibrary, .googleBooks: true
    case .appleBooks: false
    }
  }

  /// The Keychain account that holds the user's Google Books API key.
  public static let googleBooksKeyAccount = "api-key"

  private var position: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  public static func < (lhs: LookupSource, rhs: LookupSource) -> Bool {
    lhs.position < rhs.position
  }
}

public enum LookupError: Error, Hashable, Sendable {
  case offline
  case timedOut
  case refused(status: Int)
  case unreadable
  case missingKey

  /// A few words for the logs.
  public var logDescription: String {
    switch self {
    case .offline: "offline"
    case .timedOut: "timed out"
    case .refused(let status): "refused it (HTTP \(status))"
    case .unreadable: "sent something unreadable"
    case .missingKey: "needs an API key"
    }
  }
}

/// What to ask the catalogues about one book, with each field already in the shape they take.
public struct LookupQuery: Hashable, Sendable {
  public let title: String
  public let author: String?
  /// The ISBN-13 digits, when the book has a valid ISBN.
  public let isbn: String?
  /// The primary language subtag, such as "pt" for "pt_BR".
  public let language: String?

  public init(title: String, author: String?, isbn: String?, language: String?) {
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.author = Self.trimmed(author)
    self.isbn = isbn.flatMap(ISBN.normalised)
    self.language = language.flatMap(LanguageTag.primary)
  }

  private static func trimmed(_ text: String?) -> String? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
    else { return nil }
    return text
  }
}
