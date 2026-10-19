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
}
