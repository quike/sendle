import Foundation

public struct LoadLibrary: Sendable {
  private let library: any BooksLibrary
  private let inspector: any ProtectionInspector

  public init(library: any BooksLibrary, inspector: any ProtectionInspector) {
    self.library = library
    self.inspector = inspector
  }

  /// Books newest first, with DRM-protected ones marked. Only local files are inspected,
  /// so reading the library never triggers an iCloud download.
  public func callAsFunction() async throws(LibraryError) -> [Book] {
    try await library.books()
      .map { book in
        guard book.availability == .ready, inspector.isProtected(book) else { return book }
        var protected = book
        protected.availability = .protected
        return protected
      }
      .sorted { lhs, rhs in
        if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }
}
