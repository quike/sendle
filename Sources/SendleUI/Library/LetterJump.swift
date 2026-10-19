import Observation
import SendleDomain

/// The A–Z bar over a sorted list of books, the library's or a Kindle's: where each letter leads,
/// the letter at the top of the list, and the letter being dragged.
@Observable @MainActor
package final class LetterJump<ID: Hashable & Sendable> {
  /// Nil while sorted by when the books were added.
  package var index: AlphabetIndex<ID>?
  /// The book at the top of the scrolled list; setting it scrolls there.
  package var top: ID?
  /// The letter under the pointer while it drags along the bar.
  package private(set) var draggedLetter: String?
  /// The pointer is over the compact bar, which shows only then.
  package var isHovered = false

  package init() {}

  /// Sorted by title or author, with books to jump among.
  package var isShown: Bool { !(index?.lettersWithBooks.isEmpty ?? true) }

  /// The letter of the book at the top of the list.
  package var currentLetter: String? {
    top.flatMap { index?.letter(of: $0) }
  }

  /// Every letter on the full bar; only the letters with books on the compact one.
  package func letters(_ style: JumpBarStyle) -> [String] {
    style == .full ? LibraryOrder.letters : index?.lettersWithBooks ?? []
  }

  package func jump(to letter: String) {
    guard let target = index?.target(for: letter) else { return }
    top = target
  }

  package func drag(to letter: String) {
    guard letter != draggedLetter else { return }
    draggedLetter = letter
    jump(to: letter)
  }

  package func endDrag() {
    draggedLetter = nil
  }
}
