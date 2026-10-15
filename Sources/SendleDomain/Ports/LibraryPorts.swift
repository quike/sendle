import Foundation

public protocol BooksLibrary: Sendable {
  func books() async throws(LibraryError) -> [Book]
  /// Emits whenever the library may have changed.
  func changes() -> AsyncStream<Void>
}

public protocol ProtectionInspector: Sendable {
  /// True when the book's files carry DRM evidence.
  func isProtected(_ book: Book) -> Bool
}

public protocol CoverProvider: Sendable {
  /// PNG data no larger than `maxPixel` on its longest side, or nil when the book has no cover.
  func cover(for book: Book, maxPixel: Int) async -> Data?
}
