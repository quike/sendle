import CoreGraphics

/// How tall the card is: the library screen at its busiest (a Kindle plugged in, so the
/// Library | On Kindle switch shows) at rest, over two full rows of the grid and `peek` of the
/// third. With no Kindle, the third row shows more.
package enum CardHeight {
  /// How much of the third row's covers shows above the books' bottom edge.
  package static let peek: CGFloat = 25

  package static var ideal: CGFloat {
    let padding = BooksArea.screenPadding
    let grid = Theme.cardWidth - 2 * padding - 2 * BooksArea.gridInset
    let row = BookGridMetrics.rowHeight(width: grid) + BookGridMetrics.rowSpacing
    let controls =
      padding + LibraryControls.height(withKindle: true) + BooksArea.controlsGap
      + BooksArea.insets.top
    let books = BooksArea.liftRoom + 2 * row + peek
    return (controls + books + BooksArea.insets.bottom + padding).rounded(.up)
  }

  /// The whole card, or as many whole points as `available` holds.
  package static func fitting(_ available: CGFloat) -> CGFloat {
    min(ideal, available.rounded(.down))
  }
}
