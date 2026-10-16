import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CoverStoreTests {
  let moby = Book.fixture(id: "moby")
  let png = Data("png".utf8)

  @Test func readsACoverOnceAndKeepsIt() async {
    let provider = FakeCoverProvider([moby.id: png])
    let store = CoverStore(provider: provider)

    await store.load(moby, size: .large)
    await store.load(moby, size: .large)

    #expect(store.slot(for: moby, size: .large).data == png)
    #expect(provider.requests == [.init(id: moby.id, maxPixel: 360)])
  }

  @Test func remembersThatABookHasNoCover() async {
    let provider = FakeCoverProvider()
    let store = CoverStore(provider: provider)

    await store.load(moby, size: .small)
    await store.load(moby, size: .small)

    let slot = store.slot(for: moby, size: .small)
    #expect(slot.isLoaded)
    #expect(slot.data == nil)
    #expect(provider.requests.count == 1)
  }

  @Test func sharesOneReadBetweenViewsAskingAtOnce() async {
    let gate = Signal()
    let provider = FakeCoverProvider([moby.id: png], gate: gate)
    let store = CoverStore(provider: provider)

    async let first: Void = store.load(moby, size: .large)
    async let second: Void = store.load(moby, size: .large)
    #expect(await eventually { provider.requests.count == 1 })
    await gate.fire()
    _ = await (first, second)

    #expect(provider.requests.count == 1)
    #expect(store.slot(for: moby, size: .large).data == png)
  }

  @Test func keepsEachSizeApart() async {
    let provider = FakeCoverProvider([moby.id: png])
    let store = CoverStore(provider: provider)

    await store.load(moby, size: .small)
    await store.load(moby, size: .large)

    #expect(provider.requests.map(\.maxPixel) == [120, 360])
  }

  @Test func asksAgainOnceABookIsDownloaded() async {
    let provider = FakeCoverProvider([moby.id: png])
    let store = CoverStore(provider: provider)
    var cloud = moby
    cloud.availability = .inCloudOnly

    await store.load(cloud, size: .large)
    await store.load(moby, size: .large)

    #expect(provider.requests.count == 2)
    #expect(store.slot(for: moby, size: .large).data == png)
  }
}
