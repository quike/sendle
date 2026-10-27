import Foundation

/// One online catalogue.
public protocol BookCatalogue: Sendable {
  var source: LookupSource { get }
  /// The edition with `isbn` (13 digits), or nil when the catalogue has none.
  func edition(isbn: String) async throws(LookupError) -> FoundEdition?
  func editions(title: String, author: String?, language: String?) async throws(LookupError)
    -> [FoundEdition]
  /// The image at `url`, or nil when the catalogue has no real image there.
  func image(at url: URL) async throws(LookupError) -> Data?
}
