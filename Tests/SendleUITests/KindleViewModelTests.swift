import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing
import os

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
    #expect(await eventually { model.state == .reading(done: 0, total: 0) })
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

  @Test func startsListsAtTheTopWhenWhatTheyShowChanges() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    var requests = model.scrollToTopRequests
    func bumped() -> Bool {
      defer { requests = model.scrollToTopRequests }
      return model.scrollToTopRequests == requests + 1
    }
    model.query = "a"
    #expect(bumped())
    model.scope = .fromSendle
    #expect(bumped())
    model.scope = .all
    #expect(bumped())
    model.format = "txt"
    #expect(bumped())
    model.sort = .title
    #expect(bumped())
  }

  @Test func leavesTheScrollAloneWhenNothingChanged() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [])
    let requests = model.scrollToTopRequests
    model.query = ""
    model.scope = .all
    model.format = nil
    model.sort = .recent
    #expect(model.scrollToTopRequests == requests)
  }

  @Test func startsAtTheTopOnAnotherKindle() async {
    let model = makeModel()
    await model.follow(.fixture(name: "Kindle"), books: [])
    let requests = model.scrollToTopRequests
    await model.follow(.fixture(name: "Kindle Oasis"), books: [])
    #expect(model.scrollToTopRequests > requests)
  }

  @Test func manyRefreshesWhileOneWaitsReadOnce() async {
    let gate = Signal()
    kindle.gate = gate
    let model = makeModel()
    let first = Task { await model.follow(.fixture(), books: []) }
    #expect(await eventually { model.state == .reading(done: 0, total: 0) })
    let refreshes = (0..<4).map { _ in Task { await model.refresh() } }
    await gate.fire()
    await first.value
    for refresh in refreshes { await refresh.value }
    #expect(kindle.listings == 2)
  }

  @Test func aNewKindleDoesNotWaitForMatchingTheOldOne() async {
    let reader = GatedEditionReader()
    let model = KindleViewModel(
      library: kindle,
      match: MatchKindleBooks(
        editions: reader, digests: FakeFileDigester(), asins: FakeASINScheme(),
        history: InMemorySendHistoryStore()))
    kindle.result = .success(.fixture([.fixture(isbn: "9780141439518")]))
    let epub = Book.fixture(id: "epub")
    let first = Task { await model.follow(.fixture(name: "A"), books: [epub]) }
    #expect(await eventually { reader.calls == 1 })

    await model.follow(.fixture(name: "B"), books: [epub])

    #expect(model.volume == .fixture(name: "B"))
    #expect(model.matches != nil)
    await first.value
  }

  @Test func matchesFinishedForAKindleThatWentAreNeverTold() async {
    let reader = GatedEditionReader()
    let model = KindleViewModel(
      library: kindle,
      match: MatchKindleBooks(
        editions: reader, digests: FakeFileDigester(), asins: FakeASINScheme(),
        history: InMemorySendHistoryStore()))
    var told: [KindleMatches?] = []
    model.onMatchesChange = { told.append($0) }
    kindle.result = .success(
      .fixture([
        .fixture(isbn: "9780141439518"), .fixture(path: "Moby-Dick - Herman Melville.azw3"),
      ]))
    let first = Task { await model.follow(.fixture(name: "A"), books: [moby]) }
    #expect(await eventually { reader.calls == 1 })
    kindle.result = .success(.fixture([]))

    await model.follow(.fixture(name: "B"), books: [moby])
    await first.value

    #expect(told.compactMap { $0 }.allSatisfy { $0.byBook[moby.id] == nil })
    #expect(model.matches?.byBook[moby.id] == nil)
    #expect(model.matches != nil)
  }
  // MARK: Duplicates

  @Test func checksAKindleItDoesNotFollowWithoutTakingItOn() async {
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let sendlesCopy = KindleBook.fixture(
      source: .sendle, asin: "SNFNYTPPHY", asinFollowsFileName: true)
    kindle.result = .success(.fixture([]))
    kindle.setResult(.success(.fixture([sendlesCopy])), for: oasis)
    let model = makeModel()
    await model.follow(.fixture(), books: [moby])

    let check = await model.duplicates(of: [moby], on: oasis)

    #expect(check == .checked([duplicate(of: sendlesCopy)], in: .fixture([sendlesCopy])))
    #expect(kindle.listedVolumes == [.fixture(), oasis])
    #expect(model.volume == .fixture())
    #expect(model.listing == .fixture([]))
  }

  @Test func aKindleThatChangesDuringTheCheckInterruptsIt() async {
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let model = makeModel()
    await model.follow(.fixture(), books: [moby])
    let gate = Signal()
    kindle.gate = gate
    let check = Task { await model.duplicates(of: [moby], on: .fixture()) }
    #expect(await eventually { model.state == .reading(done: 0, total: 0) })

    let following = Task { await model.follow(oasis, books: [moby]) }
    #expect(await eventually { model.volume == oasis })
    await gate.fire()
    await following.value

    #expect(await check.value == .interrupted)
  }

  @Test func aKindleThatCannotBeReadSaysWhy() async {
    let model = makeModel()
    await model.follow(.fixture(), books: [moby])
    kindle.result = .failure(.unreadable("I/O error"))

    #expect(
      await model.duplicates(of: [moby], on: .fixture()) == .unreadable(.unreadable("I/O error")))
  }

  func duplicate(of copy: KindleBook) -> DuplicateCase {
    DuplicateCase(
      book: moby, edition: nil,
      match: KindleMatch(book: copy, confidence: .sure, reason: .sendleName), replace: .inPlace)
  }
}

/// Its first read waits until the reading task is cancelled, then answers as if it had finished.
final class GatedEditionReader: EditionReader {
  private let count = OSAllocatedUnfairLock(initialState: 0)

  var calls: Int { count.withLock { $0 } }

  func editions(of books: [Book]) async -> [BookID: Edition] {
    let call = count.withLock {
      $0 += 1
      return $0
    }
    if call == 1 { _ = await Signal().waitUnlessCancelled() }
    return [:]
  }
}
