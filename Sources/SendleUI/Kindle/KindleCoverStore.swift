import Foundation
import SendleDomain

/// The Kindle's covers, read from the device as views show them and kept until another Kindle is
/// followed.
@MainActor
package final class KindleCoverStore {
  private struct Key: Hashable {
    let id: KindleBookID
    /// A book copied over again gets a fresh cover.
    let modified: Date
    let size: CoverSize
  }

  private let library: any KindleLibrary
  private let cache = CoverCache<Key>()

  package init(library: any KindleLibrary) {
    self.library = library
  }

  package func slot(for book: KindleBook, size: CoverSize) -> CoverSlot {
    cache.slot(for: Key(id: book.id, modified: book.modified, size: size))
  }

  package func load(_ book: KindleBook, on volume: KindleVolume, size: CoverSize) async {
    let library = library
    await cache.load(Key(id: book.id, modified: book.modified, size: size)) {
      await library.cover(of: book, on: volume, maxPixel: size.rawValue)
    }
  }

  /// Covers belong to one Kindle; the next one starts over.
  package func reset() {
    cache.removeAll()
  }
}
