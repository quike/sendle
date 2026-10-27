import Foundation

/// One edition a catalogue found, with whatever it knows about it.
public struct FoundEdition: Hashable, Sendable {
  public let source: LookupSource
  public var title: String?
  public var author: String?
  public var year: String?
  public var isbn: String?
  public var language: String?
  public var publisher: String?
  /// The largest image the source has.
  public var cover: URL?
  /// A small image, for lists.
  public var thumbnail: URL?
  /// The edition's page at the source.
  public var link: URL?

  public init(
    source: LookupSource,
    title: String? = nil,
    author: String? = nil,
    year: String? = nil,
    isbn: String? = nil,
    language: String? = nil,
    publisher: String? = nil,
    cover: URL? = nil,
    thumbnail: URL? = nil,
    link: URL? = nil
  ) {
    self.source = source
    self.title = title
    self.author = author
    self.year = year
    self.isbn = isbn
    self.language = language
    self.publisher = publisher
    self.cover = cover
    self.thumbnail = thumbnail
    self.link = link
  }
}
