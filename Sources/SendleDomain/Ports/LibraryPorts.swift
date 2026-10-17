import Foundation

public protocol BooksLibrary: Sendable {
  func books() async throws(LibraryError) -> [Book]
  /// An independent stream per call that emits whenever the library may have changed.
  func changes() -> AsyncStream<Void>
}

public protocol ProtectionInspector: Sendable {
  /// True when the book's files carry DRM evidence.
  func isProtected(_ book: Book) -> Bool
}

public enum Cover: Hashable, Sendable {
  /// PNG data no larger than the requested size on its longest side.
  case image(Data)
  case none
  /// The book's file couldn't be read just now, so it's worth asking again later.
  case unreadable
}

public protocol CoverProvider: Sendable {
  func cover(for book: Book, maxPixel: Int) async -> Cover
}
