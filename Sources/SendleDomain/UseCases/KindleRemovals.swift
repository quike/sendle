/// Deletes a book from a Kindle with a short Undo: it holds the book, and removes it for good
/// when the next delete comes, or when the caller finalizes it once the window has passed.
public actor KindleRemovals {
  public static let undoWindow: Duration = .seconds(6)

  private let remover: any KindleBookRemover
  private let log: any ActivityLog

  /// The one delete that can still be undone.
  public private(set) var pending: HeldBook?

  public init(remover: any KindleBookRemover, log: any ActivityLog = NoActivityLog()) {
    self.remover = remover
    self.log = log
  }

  public func delete(_ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume)
    async throws(KindleRemovalError) -> HeldBook
  {
    await finalizePending()
    let held = try await remover.hold(book, listedWith: listing, on: volume)
    pending = held
    log.info(
      .usb,
      "Deleted \(Self.path(of: book)); Undo for \(Self.undoWindow.components.seconds) s")
    return held
  }

  /// Does nothing for a hold that is no longer the pending one.
  public func undo(_ held: HeldBook) async throws(KindleRemovalError) {
    guard held == pending else { return }
    try await remover.restore(held)
    pending = nil
    log.info(.usb, "Put back \(Self.path(of: held.book))")
  }

  /// Does nothing for a hold that is no longer the pending one. A failure is logged and the hold
  /// dropped, since nobody is waiting on it.
  public func finalize(_ held: HeldBook) async {
    guard held == pending else { return }
    pending = nil
    let path = Self.path(of: held.book)
    do throws(KindleRemovalError) {
      try await remover.finalize(held)
      log.info(
        .usb, "Removed \(path) for good (\(held.parts.map(\.rawValue).joined(separator: ", ")))")
    } catch {
      log.warning(.usb, "Couldn't remove \(path): \(error.detail)")
    }
  }

  public func finalizePending() async {
    if let pending { await finalize(pending) }
  }

  public func clearLeftovers(on volume: KindleVolume) async {
    let cleared = await remover.clearLeftovers(on: volume)
    guard cleared > 0 else { return }
    log.info(.usb, "Cleared \(cleared) held \(cleared == 1 ? "item" : "items") left from before")
  }

  private static func path(of book: KindleBook) -> String {
    "documents/\(book.id.relativePath)"
  }
}
