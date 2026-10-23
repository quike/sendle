import Foundation
import SendleAppleBooks
import Testing

/// A manual check against the user's own Books library. It only runs when
/// `SENDLE_REAL_LIBRARY_CHECK=1`, and the terminal needs Full Disk Access.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SENDLE_REAL_LIBRARY_CHECK"] == "1"))
struct RealLibraryCheck {
  @Test func readsTheRealLibrary() async throws {
    let books = try await AppleBooksLibrary().books()

    let counts = Dictionary(grouping: books) { "\($0.format.rawValue) \($0.availability.rawValue)" }
      .mapValues(\.count)
      .sorted { $0.key < $1.key }
    print("Books library: \(books.count) books:", counts.map { "\($0.key) \($0.value)" })
    #expect(!books.isEmpty)
  }
}
