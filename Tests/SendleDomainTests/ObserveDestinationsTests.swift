import SendleDomain
import SendleTestSupport
import Testing

struct ObserveDestinationsTests {
  @Test func listsPluggedInKindlesBeforeEmail() {
    let scribe = KindleVolume.fixture(name: "Kindle Scribe")
    let kindle = KindleVolume.fixture(name: "Kindle")

    let destinations = ObserveDestinations.destinations(email: .fixture, volumes: [scribe, kindle])

    #expect(destinations == [.usb(kindle), .usb(scribe), .email(.fixture)])
  }

  @Test func leavesEmailOutUntilItIsSetUp() {
    #expect(ObserveDestinations.destinations(email: nil, volumes: []).isEmpty)
  }

  @Test func reEmitsWhenAKindleIsPluggedIn() async {
    let monitor = FakeDestinationMonitor()
    let observe = ObserveDestinations(
      monitor: monitor, settings: InMemorySettingsStore(AppSettings(email: .fixture)))
    var updates = observe().makeAsyncIterator()

    monitor.continuation.yield([])
    #expect(await updates.next() == [.email(.fixture)])

    monitor.continuation.yield([.fixture()])
    #expect(await updates.next() == [.usb(.fixture()), .email(.fixture)])
  }
}
