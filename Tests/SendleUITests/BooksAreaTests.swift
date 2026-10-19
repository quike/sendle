import SendleUI
import Testing

struct BooksAreaTests {
  @Test func theBooksAreCutAsFarFromTheControlsAndTheCardsBottomAsTheCoversSitFromItsSides() {
    let side = BooksArea.screenPadding + BooksArea.gridInset
    #expect(side == 18)
    #expect(BooksArea.controlsGap + BooksArea.insets.top == side)
    #expect(BooksArea.screenPadding + BooksArea.insets.bottom == side)
    #expect(BooksArea.insets.leading == 0)
    #expect(BooksArea.insets.trailing == 0)
  }

  @Test func theFirstRowRestsTheLiftRoomInsideTheCut() {
    #expect(BooksArea.liftRoom == 10)
    #expect(BooksArea.controlsGap + BooksArea.insets.top + BooksArea.liftRoom == 28)
  }
}
