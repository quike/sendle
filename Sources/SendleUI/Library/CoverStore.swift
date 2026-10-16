import Foundation
import Observation
import SendleDomain

package enum CoverSize: Int, Sendable {
  /// List rows: 34 × 50 pt at 2×.
  case small = 120
  /// Grid and shelf covers: up to 117 × 175 pt at 2×.
  case large = 360
}

/// One cover a view watches. `data` stays nil for a book without a cover.
@Observable @MainActor
package final class CoverSlot {
  package fileprivate(set) var data: Data?
  package fileprivate(set) var isLoaded = false
}

/// Covers kept in memory for the app's lifetime, "no cover" included, so each is read only once.
@MainActor
public final class CoverStore {
  private struct Key: Hashable {
    let id: BookID
    let size: CoverSize
    /// A book that comes down from iCloud gets a fresh look.
    let availability: Availability
  }

  private let provider: any CoverProvider
  private var slots: [Key: CoverSlot] = [:]
  private var loads: [Key: Task<Void, Never>] = [:]

  public init(provider: any CoverProvider) {
    self.provider = provider
  }

  package func slot(for book: Book, size: CoverSize) -> CoverSlot {
    let key = Key(id: book.id, size: size, availability: book.availability)
    if let slot = slots[key] { return slot }
    let slot = CoverSlot()
    slots[key] = slot
    return slot
  }

  /// Views asking at the same time share one read.
  package func load(_ book: Book, size: CoverSize) async {
    let key = Key(id: book.id, size: size, availability: book.availability)
    let slot = slot(for: book, size: size)
    guard !slot.isLoaded else { return }
    if let running = loads[key] { return await running.value }
    let provider = provider
    let task = Task {
      slot.data = await provider.cover(for: book, maxPixel: size.rawValue)
      slot.isLoaded = true
    }
    loads[key] = task
    await task.value
    loads[key] = nil
  }
}
