import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct KindleCoverStoreTests {
  let book = KindleBook.fixture()
  let png = Data("png".utf8)

  @Test func readsEachCoverOnceAndSharesTheRead() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    async let one: Void = store.load(book, on: .fixture(), size: .large)
    async let two: Void = store.load(book, on: .fixture(), size: .large)
    _ = await (one, two)
    #expect(store.slot(for: book, size: .large).data == png)
    #expect(library.coverRequests == [book.id])
  }

  @Test func keepsACoverOnceRead() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .large)
    await store.load(book, on: .fixture(), size: .large)
    #expect(library.coverRequests.count == 1)
  }

  @Test func remembersThatABookHasNoCover() async {
    let library = FakeKindleLibrary()
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .small)
    await store.load(book, on: .fixture(), size: .small)
    let slot = store.slot(for: book, size: .small)
    #expect(slot.isLoaded)
    #expect(slot.data == nil)
    #expect(library.coverRequests.count == 1)
  }

  @Test func readsEachSizeApart() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .small)
    await store.load(book, on: .fixture(), size: .large)
    #expect(library.coverRequests.count == 2)
  }

  @Test func aChangedFileGetsAFreshCover() async {
    let library = FakeKindleLibrary()
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .small)
    await store.load(.fixture(modified: .now), on: .fixture(), size: .small)
    #expect(library.coverRequests.count == 2)
  }

  @Test func forgetsEveryCoverOnRequest() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .large)
    store.reset()
    #expect(!store.slot(for: book, size: .large).isLoaded)
    await store.load(book, on: .fixture(), size: .large)
    #expect(library.coverRequests.count == 2)
  }

  @Test func theViewModelForgetsCoversWhenAnotherKindleIsFollowed() async {
    let library = FakeKindleLibrary(
      .success(.fixture([book])), covers: [book.id: png])
    let model = makeKindleModel(reading: library)
    await model.follow(.fixture(name: "Kindle"), books: [])
    await model.covers.load(book, on: .fixture(name: "Kindle"), size: .large)
    await model.follow(.fixture(name: "Kindle Oasis"), books: [])
    #expect(!model.covers.slot(for: book, size: .large).isLoaded)
  }

  @Test func aKindleCoverIsPendingUntilItIsRead() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    #expect(store.slot(for: book, size: .large).isPending)
    await store.load(book, on: .fixture(), size: .large)
    #expect(!store.slot(for: book, size: .large).isPending)
  }

  @Test func coversArePendingAgainOnceReset() async {
    let library = FakeKindleLibrary(covers: [book.id: png])
    let store = KindleCoverStore(library: library)
    await store.load(book, on: .fixture(), size: .large)
    store.reset()
    #expect(store.slot(for: book, size: .large).isPending)
  }

  @Test func aReadStartedBeforeAResetDoesNotStandInForALaterOne() async {
    let cache = CoverCache<Int>()
    let started = Signal()
    let gate = Signal()
    let old = Task {
      await cache.load(1) {
        await started.fire()
        await gate.wait()
        return .image(Data("old".utf8))
      }
    }
    await started.wait()

    cache.removeAll()
    await cache.load(1) { .image(Data("new".utf8)) }
    await gate.fire()
    await old.value

    #expect(cache.slot(for: 1).data == Data("new".utf8))
  }
}
