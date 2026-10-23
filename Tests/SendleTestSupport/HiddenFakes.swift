import SendleDomain

public actor InMemoryHiddenBooksStore: HiddenBooksStore {
  private var stored: Set<BookID>
  private var failure: StorageError?

  public init(_ hidden: Set<BookID> = [], failure: StorageError? = nil) {
    stored = hidden
    self.failure = failure
  }

  /// Writes from now on throw `failure`, or succeed again when it is nil.
  public func fail(with failure: StorageError?) {
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
