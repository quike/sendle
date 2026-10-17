import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ObserveDestinationsTests {
  @Test func listsPluggedInKindlesBeforeEmail() {
    let scribe = KindleVolume.fixture(name: "Kindle Scribe")
    let kindle = KindleVolume.fixture(name: "Kindle")

    let destinations = ObserveDestinations.destinations(email: .fixture, volumes: [scribe, kindle])

    #expect(destinations == [.usb(kindle), .usb(scribe), .email(.fixture)])
  }

  @Test func ordersKindlesWithTheSameNameByID() {
    let second = KindleVolume(
      id: "/Volumes/Kindle 1", name: "Kindle", mountURL: URL(filePath: "/Volumes/Kindle 1"))
    let first = KindleVolume(
      id: "/Volumes/Kindle", name: "Kindle", mountURL: URL(filePath: "/Volumes/Kindle"))

    let destinations = ObserveDestinations.destinations(email: nil, volumes: [second, first])

    #expect(destinations == [.usb(first), .usb(second)])
  }

  @Test func leavesEmailOutUntilItIsSetUp() {
    #expect(ObserveDestinations.destinations(email: nil, volumes: []).isEmpty)
  }

  @Test func reEmitsWhenAKindleIsPluggedIn() async {
    let monitor = FakeDestinationMonitor()
    let observe = ObserveDestinations(
      monitor: monitor, settings: InMemorySettingsStore(AppSettings(email: .fixture)))
    var updates = observe().makeAsyncIterator()

    #expect(await updates.next() == [.email(.fixture)])

    monitor.update([.fixture()])
    #expect(await updates.next() == [.usb(.fixture()), .email(.fixture)])
  }

  @Test func everyListenerGetsEveryChange() async {
    let monitor = FakeDestinationMonitor()
    let observe = ObserveDestinations(monitor: monitor, settings: InMemorySettingsStore())
    var first = observe().makeAsyncIterator()
    var second = observe().makeAsyncIterator()

    monitor.update([.fixture()])

    #expect(await first.next() == [])
    #expect(await first.next() == [.usb(.fixture())])
    #expect(await second.next() == [])
    #expect(await second.next() == [.usb(.fixture())])
  }

  @Test func endsWhenTheMonitorEnds() async {
    let monitor = FakeDestinationMonitor()
    let observe = ObserveDestinations(monitor: monitor, settings: InMemorySettingsStore())
    var updates = observe().makeAsyncIterator()
    #expect(await updates.next() == [])

    monitor.finish()

    #expect(await updates.next() == nil)
  }

  @Test func stopsWatchingKindlesWhenNobodyListens() async {
    let monitor = FakeDestinationMonitor()
    let observe = ObserveDestinations(monitor: monitor, settings: InMemorySettingsStore())

    let listener = Task {
      for await _ in observe() {}
    }
    #expect(await eventually { monitor.subscriberCount == 1 })
    listener.cancel()

    #expect(await eventually { monitor.subscriberCount == 0 })
  }
}
