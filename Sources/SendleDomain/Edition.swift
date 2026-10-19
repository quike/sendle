import Foundation

/// What a library EPUB's package says about the edition it is.
public struct Edition: Hashable, Sendable, Codable {
  public var key: String?
  public var isbn: String?
  public var publisher: String?

  public init(key: String? = nil, isbn: String? = nil, publisher: String? = nil) {
    self.key = key
    self.isbn = isbn
    self.publisher = publisher
  }

  /// The key without surrounding whitespace, or nil when nothing is left.
  public var trimmedKey: String? {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
      return nil
    }
    return key
  }
}
