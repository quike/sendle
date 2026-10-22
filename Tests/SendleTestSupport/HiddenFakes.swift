import SendleDomain

public actor InMemoryHiddenBooksStore: HiddenBooksStore {
  private var stored: Set<BookID>
  private let failure: StorageError?

  public init(_ hidden: Set<BookID> = [], failure: StorageError? = nil) {
    stored = hidden
    self.failure = failure
  }

  public func hidden() -> Set<BookID> {
    stored
  }

  public func set(_ books: Set<BookID>, hidden: Bool) throws(StorageError) {
    if let failure { throw failure }
    if hidden {
      stored.formUnion(books)
    } else {
      stored.subtract(books)
    }
  }
}
