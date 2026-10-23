import Foundation

/// What a library EPUB's package says about the edition it is.
public struct Edition: Hashable, Sendable, Codable {
  public var key: String?
  public var isbn: String?
  public var publisher: String?
  /// Four digits, from the package's first `dc:date`.
  public var year: String?

  public init(
    key: String? = nil, isbn: String? = nil, publisher: String? = nil, year: String? = nil
  ) {
    self.key = key
    self.isbn = isbn
    self.publisher = publisher
    self.year = year
  }

  /// The key without surrounding whitespace, or nil when nothing is left.
  public var trimmedKey: String? {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
      return nil
    }
    return key
  }
}
