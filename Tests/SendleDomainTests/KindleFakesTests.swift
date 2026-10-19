import SendleDomain
import SendleTestSupport
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KindleFakesTests {
  func list(_ library: FakeKindleLibrary) async -> KindleListingError? {
    do {
      _ = try await library.listing(of: .fixture()) { _, _ in }
      return nil
    } catch {
      return error
    }
  }

  @Test func aGatedListingWaitsForTheGate() async {
    let gate = Signal()
    let library = FakeKindleLibrary()
    library.gate = gate
    let task = Task { await list(library) }
    #expect(await eventually { library.listings == 1 })
    await gate.fire()
    #expect(await task.value == nil)
  }

  @Test func aCancelledGatedListingThrowsCancelled() async {
    let library = FakeKindleLibrary()
    library.gate = Signal()
    let task = Task { await list(library) }
    #expect(await eventually { library.listings == 1 })
    task.cancel()
    #expect(await task.value == .cancelled)
  }
}
