import Foundation
import SendleDomain

public struct FakeBooksLibrary: BooksLibrary {
  public var result: Result<[Book], LibraryError>

  public init(_ result: Result<[Book], LibraryError>) {
    self.result = result
  }

  public func books() async throws(LibraryError) -> [Book] {
    try result.get()
  }

  public func changes() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }
}

public struct StubProtectionInspector: ProtectionInspector {
  public var protectedIDs: Set<BookID>

  public init(protectedIDs: Set<BookID> = []) {
    self.protectedIDs = protectedIDs
  }

  public func isProtected(_ book: Book) -> Bool {
    protectedIDs.contains(book.id)
  }
}
