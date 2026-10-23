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
  /// True until the first answer, whatever it is, so a view shows a skeleton and not a title card.
  package fileprivate(set) var isPending = true
}

/// Covers kept in memory, "no cover" included, so each is read only once. A cover that couldn't
/// be read is asked for again the next time a view shows it.
@MainActor
package final class CoverCache<Key: Hashable> {
  private var slots: [Key: CoverSlot] = [:]
  private var loads: [Key: Task<Void, Never>] = [:]

  package init() {}

  package func slot(for key: Key) -> CoverSlot {
    if let slot = slots[key] { return slot }
    let slot = CoverSlot()
    slots[key] = slot
    return slot
  }

  /// Views asking at the same time share one read.
  package func load(_ key: Key, read: @escaping @Sendable () async -> Cover) async {
    let slot = slot(for: key)
    guard !slot.isLoaded else { return }
    if let running = loads[key] { return await running.value }
    let task = Task {
      defer { slot.isPending = false }
      switch await read() {
      case .image(let png):
        slot.data = png
        slot.isLoaded = true
      case .none:
        slot.isLoaded = true
      case .unreadable:
        break
      }
    }
    loads[key] = task
    await task.value
    if loads[key] == task { loads[key] = nil }
  }

  package func removeAll() {
    slots = [:]
    loads = [:]
  }
}

/// The library's covers, read from the books' files for the app's lifetime.
@MainActor
public final class CoverStore {
  private struct Key: Hashable {
    let id: BookID
    let size: CoverSize
    /// A book that comes down from iCloud gets a fresh look.
    let availability: Availability
    /// The chosen cover's file name, which changes with the image.
    let edit: String?
  }

  private let provider: any CoverProvider
  private let cache = CoverCache<Key>()

  public init(provider: any CoverProvider) {
    self.provider = provider
  }

  private func key(for book: Book, size: CoverSize) -> Key {
    Key(
      id: book.id, size: size, availability: book.availability,
      edit: book.edits.cover?.lastPathComponent)
  }

  package func slot(for book: Book, size: CoverSize) -> CoverSlot {
    cache.slot(for: key(for: book, size: size))
  }

  package func load(_ book: Book, size: CoverSize) async {
    let provider = provider
    await cache.load(key(for: book, size: size)) {
      await provider.cover(for: book, maxPixel: size.rawValue)
    }
  }
}
