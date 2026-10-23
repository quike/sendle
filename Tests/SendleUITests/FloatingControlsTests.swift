import CoreGraphics
import SendleDomain
import SendleUI
import SwiftUI
import Testing

struct FloatingControlsTests {
  let screen = CGRect(x: 0, y: 0, width: 1_440, height: 875)

  // MARK: Side

  @Test func theAZCardGoesRightOfTheCardWhenTheScreenHasRoom() {
    let card = CGRect(x: 412, y: 246, width: 400, height: 620)
    #expect(FloatingControls.side(card: card, screen: screen, width: 24, gap: 10) == .trailing)
  }

  @Test func theAZCardMirrorsToTheLeftNearTheScreensRightEdge() {
    let card = CGRect(x: 1_036, y: 246, width: 400, height: 620)
    #expect(FloatingControls.side(card: card, screen: screen, width: 24, gap: 10) == .leading)
  }

  @Test func justEnoughRoomOnTheRightIsEnough() {
    let card = CGRect(x: 1_006, y: 246, width: 400, height: 620)
    #expect(FloatingControls.side(card: card, screen: screen, width: 24, gap: 10) == .trailing)
    let tooFar = card.offsetBy(dx: 1, dy: 0)
    #expect(FloatingControls.side(card: tooFar, screen: screen, width: 24, gap: 10) == .leading)
  }

  @Test func aScreenThatDoesNotStartAtZeroCountsFromItsOwnEdge() {
    let second = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
    let card = CGRect(x: -500, y: 400, width: 400, height: 620)
    #expect(FloatingControls.side(card: card, screen: second, width: 24, gap: 10) == .trailing)
    #expect(
      FloatingControls.side(card: card.offsetBy(dx: 90, dy: 0), screen: second, width: 24, gap: 10)
        == .leading)
  }

  // MARK: Margins

  /// Each floating card takes the gap, itself and the same room for its shadow as the card.
  @Test func theFloatingCardsGrowOnlyTheEdgesTheyUse() {
    let base = PanelView.margins
    let right = FloatingControls.margins(side: .trailing)
    #expect(right.top == base.top)
    #expect(right.leading == base.leading)
    #expect(right.trailing == base.trailing + 10 + FloatingControls.railWidth)
    #expect(right.bottom == base.bottom + 10 + FloatingControls.sendHeight)

    let left = FloatingControls.margins(side: .leading)
    #expect(left.leading == right.trailing)
    #expect(left.trailing == base.trailing)
    #expect(left.bottom == right.bottom)
  }

  @Test func theWindowIsTheCardAndItsMargins() {
    let margins = FloatingControls.margins(side: .leading)
    #expect(
      PanelView.windowSize(margins: margins)
        == CGSize(
          width: Theme.cardSize.width + margins.leading + margins.trailing,
          height: Theme.cardSize.height + margins.top + margins.bottom))
    #expect(PanelView.windowSize(margins: PanelView.margins) == PanelView.windowSize)
  }

  // MARK: Cards

  @Test func theSendCardIsTheCardsWidthAGapBelowIt() {
    let card = CGRect(x: 24, y: 12, width: 400, height: 620)
    #expect(
      FloatingControls.sendFrame(card: card)
        == CGRect(x: 24, y: 642, width: 400, height: FloatingControls.sendHeight))
  }

  @Test func theFullAZCardIsTheBooksHeightAGapBesideTheCard() {
    let card = CGRect(x: 58, y: 12, width: 400, height: 620)
    let books = CGRect(x: 72, y: 250, width: 372, height: 368)
    let width = FloatingControls.railWidth
    #expect(
      FloatingControls.railFrame(card: card, books: books, side: .trailing, height: nil)
        == CGRect(x: 468, y: 250, width: width, height: 368))
    #expect(
      FloatingControls.railFrame(card: card, books: books, side: .leading, height: nil)
        == CGRect(x: 58 - 10 - width, y: 250, width: width, height: 368))
  }

  @Test func theCompactAZCardFitsItsLettersCentredOnTheBooks() {
    let card = CGRect(x: 24, y: 12, width: 400, height: 620)
    let books = CGRect(x: 38, y: 250, width: 372, height: 368)
    #expect(
      FloatingControls.railFrame(card: card, books: books, side: .trailing, height: 100)
        == CGRect(x: 434, y: 384, width: FloatingControls.railWidth, height: 100))
    #expect(
      FloatingControls.railFrame(card: card, books: books, side: .trailing, height: 900).height
        == 368)
  }

  // MARK: Window

  /// The status item near the screen's right edge, as it usually is.
  let anchor = CGRect(x: 1_300, y: 875, width: 24, height: 25)
  /// The card's top edge under that status item: 3 pt into it, less the arrow's room.
  let cardTop: CGFloat = 875 + 3 - 12
  let height = Theme.cardSize.height

  @Test func theCardSitsUnderTheStatusItemAsItAlwaysHas() {
    let placement = PanelPlacement(below: anchor, in: screen)

    #expect(placement.card == CGRect(x: 1_036, y: cardTop - height, width: 400, height: height))
    #expect(placement.arrowX == 276)
  }

  @Test func theWindowGrowsAroundTheCardForTheFloatingCards() {
    let placement = PanelPlacement(below: anchor, in: screen)

    #expect(placement.side == .leading)
    let margins = FloatingControls.margins(side: .leading)
    #expect(placement.margins == margins)
    #expect(
      placement.window
        == CGRect(
          x: 1_036 - margins.leading, y: cardTop - height - margins.bottom,
          width: 400 + margins.leading + margins.trailing,
          height: height + margins.top + margins.bottom))
  }

  @Test func aStatusItemFarFromTheEdgeKeepsTheAZCardOnTheRight() {
    let middle = CGRect(x: 600, y: 875, width: 24, height: 25)
    let floating = PanelPlacement(below: middle, in: screen)

    #expect(floating.card == CGRect(x: 412, y: cardTop - height, width: 400, height: height))
    #expect(floating.side == .trailing)
    #expect(floating.window.minX == 412 - PanelView.margins.leading)
  }

  // MARK: Screen height

  @Test func aScreenWithRoomKeepsTheWholeCardAboveItsBottom() {
    let placement = PanelPlacement(below: anchor, in: screen)

    #expect(placement.card.height == CardHeight.ideal)
    #expect(placement.window.minY > screen.minY)
  }

  /// A short screen, its Dock taking the bottom 70 pt: the card keeps its top under the status
  /// item and gives up height, so the window, the send card's room included, ends at the Dock.
  @Test func aShortScreenShrinksTheCardSoTheWindowEndsAtItsBottom() {
    let short = CGRect(x: 0, y: 70, width: 1_280, height: 600)
    let statusItem = CGRect(x: 1_150, y: 670, width: 24, height: 25)
    let placement = PanelPlacement(below: statusItem, in: short)

    let margins = placement.margins
    let top: CGFloat = 670 + 3 - 12
    #expect(placement.card.maxY == top)
    #expect(placement.window.minY == short.minY)
    #expect(placement.card.height == top - margins.bottom - 70)
    #expect(placement.card.height < CardHeight.ideal)
    #expect(placement.card.width == Theme.cardSize.width)
    #expect(
      placement.window.size
        == PanelView.windowSize(margins: margins, card: placement.card.size))
  }

  @Test func aShortScreenKeepsTheArrowAndTheSideItWouldHave() {
    let short = CGRect(x: 0, y: 0, width: 1_440, height: 560)
    let statusItem = CGRect(x: 1_300, y: 560, width: 24, height: 25)
    let placement = PanelPlacement(below: statusItem, in: short)

    #expect(placement.card.minX == 1_036)
    #expect(placement.arrowX == 276)
    #expect(placement.side == .leading)
  }
}
