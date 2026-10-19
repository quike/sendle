import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct KindleViewModelTests {
  let kindle = FakeKindleLibrary(
    .success(
      .fixture([
        .fixture(source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true),
        .fixture(path: "a.txt"), .fixture(path: "b.txt"),
      ])))
  let moby = Book.fixture(id: "moby")

  func makeModel() -> KindleViewModel {
    makeKindleModel(reading: kindle)
  }

  @Test func readsTheKindleAndMatchesTheLibrary() async {
    let model = makeModel()
    var told: [KindleMatches?] = []
    model.onMatchesChange = { told.append($0) }
    await model.follow(.fixture(), books: [moby])
    #expect(model.state == .loaded)
    #expect(model.subtitle == "Kindle · 3 books · 3.1 GB free")
    #expect(told.last??.byBook[moby.id]?.confidence == .sure)
  }

  @Test func countsOneBookInTheSingular() async {
    kindle.result = .success(.fixture([.fixture()], freeBytes: nil))
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    #expect(model.subtitle == "Kindle · 1 book")
  }

  @Test func showsProgressWhileReading() async {
    kindle.progress = [(120, 214)]
    let gate = Signal()
    kindle.gate = gate
    let model = makeModel()
    let reading = Task { await model.follow(.fixture(), books: []) }
    #expect(await eventually { model.subtitle == "Reading Kindle… 120 of 214" })
    await gate.fire()
    await reading.value
  }

  @Test func saysItIsReadingBeforeItKnowsHowMany() async {
    let gate = Signal()
    kindle.gate = gate
    let model = makeModel()
    let reading = Task { await model.follow(.fixture(), books: []) }
    #expect(await eventually { model.subtitle == "Reading Kindle…" })
    await gate.fire()
    await reading.value
  }

  @Test func keepsTheBooksOnScreenWhileRefreshing() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    let gate = Signal()
    kindle.gate = gate
    let refreshing = Task { await model.refresh() }
    #expect(await eventually { model.state == .reading(done: 0, total: 0) })
    #expect(model.listing?.books.count == 3)
    await gate.fire()
    await refreshing.value
    #expect(model.state == .loaded)
  }

  @Test func forgetsTheKindleWhenItGoes() async {
    let model = makeModel()
    var told: [KindleMatches?] = []
    model.onMatchesChange = { told.append($0) }
    await model.follow(.fixture(), books: [moby])
    await model.follow(nil, books: [moby])
    #expect(model.state == .idle)
    #expect(model.listing == nil)
    #expect(model.volume == nil)
    #expect(told.last == .some(nil))
  }

  @Test func aKindleThatGoesMidReadLeavesNothingBehind() async {
    let gate = Signal()
    kindle.gate = gate
    let model = makeModel()
    let reading = Task { await model.follow(.fixture(), books: [moby]) }
    #expect(await eventually { model.state == .reading(done: 0, total: 0) })
    await model.follow(nil, books: [moby])
    await gate.fire()
    await reading.value
    #expect(model.state == .idle)
    #expect(model.listing == nil)
    #expect(model.matches == nil)
  }

  @Test func aRefreshDuringAReadWaitsForIt() async {
    let gate = Signal()
    kindle.gate = gate
    let model = makeModel()
    let first = Task { await model.follow(.fixture(), books: []) }
    let second = Task { await model.refresh() }
    await gate.fire()
    await first.value
    await second.value
    #expect(kindle.listings == 2)
    #expect(kindle.maxConcurrentListings == 1)
  }

  @Test func aRefreshWithoutAKindleReadsNothing() async {
    let model = makeModel()
    await model.refresh()
    #expect(kindle.listings == 0)
    #expect(model.state == .idle)
  }

  @Test func rematchesWhenTheLibraryChangesWithoutReadingAgain() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    await model.follow(.fixture(), books: [moby])
    #expect(kindle.listings == 1)
    #expect(model.matches?.byBook[moby.id] != nil)
  }

  @Test func theSameBooksAreNotMatchedAgain() async {
    let model = makeModel()
    var told = 0
    model.onMatchesChange = { _ in told += 1 }
    await model.follow(.fixture(), books: [moby])
    await model.follow(.fixture(), books: [moby])
    #expect(told == 1)
  }

  @Test func rematchMatchesAgainstTheListingAlreadyRead() async {
    let model = makeModel()
    var told = 0
    model.onMatchesChange = { _ in told += 1 }
    await model.follow(.fixture(), books: [moby])
    await model.rematch()
    #expect(told == 2)
    #expect(kindle.listings == 1)
  }

  @Test func anotherKindleIsReadAfresh() async {
    let model = makeModel()
    await model.follow(.fixture(name: "Kindle"), books: [moby])
    await model.follow(.fixture(name: "Kindle Oasis"), books: [moby])
    #expect(kindle.listings == 2)
    #expect(model.volume == .fixture(name: "Kindle Oasis"))
    #expect(model.subtitle == "Kindle Oasis · 3 books · 3.1 GB free")
  }

  @Test func aFailedReadSaysWhy() async {
    kindle.result = .failure(.unreadable("I/O error"))
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    #expect(
      model.state
        == .failed(
          Problem("Couldn't read Kindle", message: "I/O error", fix: Fix("Try again", .retry))))
    #expect(model.subtitle == "Couldn't read Kindle")
    #expect(model.listing == nil)
  }

  @Test func anUnpluggedKindleSaysSo() async {
    kindle.result = .failure(.deviceDisconnected)
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    #expect(
      model.state
        == .failed(
          Problem("Kindle was unplugged", message: "Plug it in again to see its books.")))
  }

  @Test func aFailedRefreshForgetsTheOldMatches() async {
    let model = makeModel()
    var told: [KindleMatches?] = []
    model.onMatchesChange = { told.append($0) }
    await model.follow(.fixture(), books: [moby])
    kindle.result = .failure(.unreadable("I/O error"))
    await model.refresh()
    #expect(model.matches == nil)
    #expect(told.last == .some(nil))
  }

  @Test func aCancelledReadKeepsWhatWasThere() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    kindle.result = .failure(.cancelled)
    await model.refresh()
    #expect(model.state == .loaded)
    #expect(model.listing?.books.count == 3)
  }

  @Test func aReadAfterAFailureCanSucceed() async {
    kindle.result = .failure(.unreadable("I/O error"))
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    kindle.result = .success(.fixture([.fixture()]))
    await model.refresh()
    #expect(model.state == .loaded)
    #expect(model.listing?.books.count == 1)
  }
}
