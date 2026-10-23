import AppKit
import SendleDomain
import SendleTestSupport
import SendleUI
import SwiftUI
import Testing

/// The card is as tall as the library screen at its busiest (a Kindle plugged in, so the
/// Library | On Kindle switch shows; floating controls; the grid at rest) needs for two full rows
/// of books and a peek of the third.
struct CardHeightTests {
  /// The grid's width: the card less the screen's padding and the grid's inset at each side.
  let gridWidth = Theme.cardWidth - 2 * BooksArea.screenPadding - 2 * BooksArea.gridInset

  /// How much of the third row's cover shows above the books' bottom cut, at rest.
  func peek(withKindle: Bool, cardHeight: CGFloat) -> CGFloat {
    let booksTop =
      BooksArea.screenPadding + LibraryControls.height(withKindle: withKindle)
      + BooksArea.controlsGap + BooksArea.insets.top
    let row = BookGridMetrics.rowHeight(width: gridWidth) + BookGridMetrics.rowSpacing
    let thirdRow = booksTop + BooksArea.liftRoom + 2 * row
    let bottomCut = cardHeight - BooksArea.insets.bottom - BooksArea.screenPadding
    return bottomCut - thirdRow
  }

  @Test func aGridRowIsACoverAtTheColumnsWidthWithItsTitleAndByline() {
    #expect(gridWidth == 364)
    // Three columns 10 pt apart: 114.67 pt wide, so 172 pt tall at 2:3.
    let cover: CGFloat = 172
    #expect(BookGridMetrics.rowHeight(width: 364) == cover + 6 + 13 + 12)
  }

  @Test func theControlsAboveTheBooksAreTheRowsTheScreenStacks() {
    let header: CGFloat = 34
    let sideSwitch: CGFloat = 12 + 26
    let below: CGFloat = 26 + 10 + 31 + 9 + 21 + 8 + 24
    #expect(LibraryControls.height(withKindle: true) == header + sideSwitch + 8 + below)
    #expect(LibraryControls.height(withKindle: false) == header + 12 + below)
  }

  @Test func theCardShowsTwoFullRowsAndAPeekOfTheThirdUnderTheBusiestControls() {
    #expect(CardHeight.peek == 25)
    #expect(peek(withKindle: true, cardHeight: CardHeight.ideal) == 25)
    #expect(Theme.cardSize == CGSize(width: Theme.cardWidth, height: CardHeight.ideal))
  }

  @Test func withoutAKindleTheThirdRowPeeksByTheSideSwitchsRoomMore() {
    let saved = LibraryControls.height(withKindle: true) - LibraryControls.height(withKindle: false)
    #expect(saved == 34)
    #expect(peek(withKindle: false, cardHeight: CardHeight.ideal) == 25 + saved)
  }

  @MainActor
  @Test func theFilterBarIsAsTallAsItsScopesAndItsMenus() async {
    let settings = InMemorySettingsStore(AppSettings(email: .fixture))
    let model = LibraryViewModel(
      loadLibrary: LoadLibrary(
        library: FakeBooksLibrary(.success([])), inspector: StubProtectionInspector()),
      observeDestinations: ObserveDestinations(
        monitor: FakeDestinationMonitor(), settings: settings),
      settings: settings, history: InMemorySendHistoryStore(),
      converter: FakeFormatConverter(isAvailable: false))
    await model.start()
    model.showKindleMatches(.empty)
    let height = NSHostingView(rootView: FilterBar(library: model)).fittingSize.height

    #expect(
      height == LibraryControls.scopes + LibraryControls.filterSpacing + LibraryControls.menus)
  }

  // MARK: Screen

  @Test func aScreenWithRoomGetsTheWholeCard() {
    #expect(CardHeight.fitting(2_000) == CardHeight.ideal)
    #expect(CardHeight.fitting(CardHeight.ideal) == CardHeight.ideal)
  }

  @Test func aShortScreenShrinksTheCardToWholePointsThatFit() {
    #expect(CardHeight.fitting(CardHeight.ideal - 0.5) == CardHeight.ideal - 1)
    #expect(CardHeight.fitting(480.7) == 480)
  }
}
