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

  @Test func attachedControlsKeepTodaysMargins() {
    #expect(FloatingControls.margins(.attached, side: .trailing) == PanelView.margins)
    #expect(FloatingControls.margins(.attached, side: .leading) == PanelView.margins)
  }

  /// Each floating card takes the gap, itself and the same room for its shadow as the card.
  @Test func floatingControlsGrowOnlyTheEdgesTheirCardsUse() {
    let base = PanelView.margins
    let right = FloatingControls.margins(.floating, side: .trailing)
    #expect(right.top == base.top)
    #expect(right.leading == base.leading)
    #expect(right.trailing == base.trailing + 10 + FloatingControls.railWidth)
    #expect(right.bottom == base.bottom + 10 + FloatingControls.sendHeight)

    let left = FloatingControls.margins(.floating, side: .leading)
    #expect(left.leading == right.trailing)
    #expect(left.trailing == base.trailing)
    #expect(left.bottom == right.bottom)
  }

  @Test func theWindowIsTheCardAndItsMargins() {
    let margins = FloatingControls.margins(.floating, side: .leading)
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

  @Test func attachedControlsPlaceTheWindowAsBefore() {
    let placement = PanelPlacement(below: anchor, in: screen, controls: .attached)

    #expect(placement.window == CGRect(x: 1_012, y: 200, width: 448, height: 678))
    #expect(placement.card == CGRect(x: 1_036, y: 246, width: 400, height: 620))
    #expect(placement.margins == PanelView.margins)
    #expect(placement.arrowX == 276)
  }

  @Test func floatingControlsGrowTheWindowAroundACardThatStaysPut() {
    let attached = PanelPlacement(below: anchor, in: screen, controls: .attached)
    let floating = PanelPlacement(below: anchor, in: screen, controls: .floating)

    #expect(floating.card == attached.card)
    #expect(floating.arrowX == attached.arrowX)
    #expect(floating.side == .leading)
    let margins = FloatingControls.margins(.floating, side: .leading)
    #expect(floating.margins == margins)
    #expect(
      floating.window
        == CGRect(
          x: 1_036 - margins.leading, y: 246 - margins.bottom,
          width: 400 + margins.leading + margins.trailing,
          height: 620 + margins.top + margins.bottom))
  }

  @Test func aStatusItemFarFromTheEdgeKeepsTheAZCardOnTheRight() {
    let middle = CGRect(x: 600, y: 875, width: 24, height: 25)
    let floating = PanelPlacement(below: middle, in: screen, controls: .floating)

    #expect(floating.card == CGRect(x: 412, y: 246, width: 400, height: 620))
    #expect(floating.side == .trailing)
    #expect(floating.window.minX == 412 - PanelView.margins.leading)
  }
}
