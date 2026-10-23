import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

struct SelectionTests {
  /// Books a…f (or `ids`) in grid order; `blocked` ones can't be sent.
  func items(
    _ ids: [String] = ["a", "b", "c", "d", "e", "f"],
    blocked: Set<String> = []
  ) -> [BookItemViewModel] {
    let books = ids.map {
      Book.fixture(id: $0, availability: blocked.contains($0) ? .missing : .ready)
    }
    return LibraryItems.make(
      books: books, sends: [:], hidden: [], filter: .all, format: nil, query: "",
      destination: .email,
      converterAvailable: false, kindle: nil, now: Date())
  }

  func ids(_ selection: Selection) -> [String] {
    selection.ids.map(\.rawValue).sorted()
  }

  func id(_ raw: String) -> BookID { BookID(rawValue: raw) }

  @Test func aClickSelectsOnlyThatBook() {
    var selection = Selection()
    selection.click(id("a"), .plain, in: items())
    selection.click(id("c"), .plain, in: items())

    #expect(ids(selection) == ["c"])
  }

  @Test func clickingTheOnlySelectedBookKeepsIt() {
    var selection = Selection()
    selection.click(id("a"), .plain, in: items())
    selection.click(id("a"), .plain, in: items())

    #expect(ids(selection) == ["a"])
  }

  @Test func commandClickAddsOrRemovesOneBook() {
    var selection = Selection()
    selection.click(id("a"), .plain, in: items())
    selection.click(id("c"), .toggle, in: items())
    #expect(ids(selection) == ["a", "c"])

    selection.click(id("a"), .toggle, in: items())
    #expect(ids(selection) == ["c"])
  }

  @Test func shiftClickAddsTheRangeFromTheLastClickSkippingBlockedBooks() {
    var selection = Selection()
    selection.click(id("b"), .plain, in: items(blocked: ["d"]))
    selection.click(id("e"), .range, in: items(blocked: ["d"]))

    #expect(ids(selection) == ["b", "c", "e"])
  }

  @Test func booksThatCannotBeSentAreNeverSelected() {
    var selection = Selection()
    selection.click(id("d"), .plain, in: items(blocked: ["d"]))
    #expect(selection.isEmpty)

    selection.selectAll(in: items(blocked: ["d"]))
    #expect(ids(selection) == ["a", "b", "c", "e", "f"])
  }

  @Test func arrowsSelectTheNextSendableBook() {
    var selection = Selection()
    selection.click(id("c"), .plain, in: items(blocked: ["d"]))

    selection.move(.right, columns: 3, in: items(blocked: ["d"]))

    #expect(ids(selection) == ["e"])
  }

  @Test func upAndDownMoveByARowInTheGrid() {
    var selection = Selection()
    selection.click(id("b"), .plain, in: items())

    selection.move(.down, columns: 3, in: items())
    #expect(ids(selection) == ["e"])

    selection.move(.up, columns: 3, in: items())
    #expect(ids(selection) == ["b"])
  }

  @Test func arrowsMoveOnFromTheBookShiftClickedLast() {
    var selection = Selection()
    selection.click(id("b"), .plain, in: items())
    selection.click(id("d"), .range, in: items())

    selection.move(.right, columns: 3, in: items())

    #expect(ids(selection) == ["e"])
  }

  @Test func upAndDownKeepTheColumnPastABlockedBook() {
    let grid = items(["a", "b", "c", "d", "e", "f", "g", "h", "i"], blocked: ["e"])
    var selection = Selection()
    selection.click(id("b"), .plain, in: grid)

    selection.move(.down, columns: 3, in: grid)
    #expect(ids(selection) == ["h"])

    selection.move(.up, columns: 3, in: grid)
    #expect(ids(selection) == ["b"])
  }

  @Test func anArrowAfterSelectAllKeepsOnlyTheLastBook() {
    var selection = Selection()
    selection.selectAll(in: items())

    selection.move(.down, columns: 1, in: items())
    #expect(ids(selection) == ["f"])

    selection.move(.up, columns: 1, in: items())
    #expect(ids(selection) == ["e"])
  }

  @Test func arrowsStartFromTheEdgesWhenNothingIsSelected() {
    var down = Selection()
    down.move(.down, columns: 1, in: items(blocked: ["a"]))
    var up = Selection()
    up.move(.up, columns: 1, in: items())

    #expect(ids(down) == ["b"])
    #expect(ids(up) == ["f"])
  }

  @Test func arrowsFromAnEdgeSkipABlockedBookOneAtATime() {
    var down = Selection()
    down.move(.down, columns: 3, in: items(blocked: ["a"]))
    var up = Selection()
    up.move(.up, columns: 3, in: items(blocked: ["f"]))

    #expect(ids(down) == ["b"])
    #expect(ids(up) == ["e"])
  }

  @Test func arrowsStopAtTheEnds() {
    var selection = Selection()
    selection.click(id("f"), .plain, in: items())

    selection.move(.right, columns: 3, in: items())
    selection.move(.down, columns: 3, in: items())

    #expect(ids(selection) == ["f"])
  }

  @Test func keepsOnlyBooksStillShownAndSendable() {
    var selection = Selection()
    selection.selectAll(in: items())

    selection.keep(in: Array(items(blocked: ["b"]).prefix(3)))

    #expect(ids(selection) == ["a", "c"])
  }
}
