import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct KindleVolumeMonitorTests {
  let kindle: MountedVolume
  let other: MountedVolume

  init() throws {
    kindle = MountedVolume(url: try makeVolumeRoot(), name: "Kindle")
    other = MountedVolume(url: try makeVolumeRoot(folders: ["Photos"]), name: "Backup")
  }

  func expected(_ volume: MountedVolume) -> KindleVolume {
    KindleVolume(
      id: volume.url.path(percentEncoded: false), name: volume.name, mountURL: volume.url)
  }

  @Test func startsWithTheKindlesAlreadyPluggedIn() async {
    let monitor = KindleVolumeMonitor(source: FakeVolumeSource([other, kindle]))
    var updates = monitor.volumes().makeAsyncIterator()

    #expect(await updates.next() == [expected(kindle)])
  }

  @Test func followsAKindleBeingPluggedInAndOut() async {
    let source = FakeVolumeSource()
    var updates = KindleVolumeMonitor(source: source).volumes().makeAsyncIterator()
    #expect(await updates.next() == [])

    source.mount(kindle)
    #expect(await updates.next() == [expected(kindle)])

    source.unmount(kindle)
    #expect(await updates.next() == [])
  }

  @Test func logsKindlesComingAndGoing() async {
    let source = FakeVolumeSource([kindle])
    let log = FakeActivityLog()
    var updates = KindleVolumeMonitor(source: source, log: log).volumes().makeAsyncIterator()
    _ = await updates.next()

    source.unmount(kindle)
    _ = await updates.next()

    #expect(
      log.summary == [
        "info USB Kindle is plugged in at \(kindle.url.path(percentEncoded: false))",
        "info USB Kindle was unplugged or ejected",
      ])
  }

  @Test func staysQuietWhileOtherVolumesComeAndGo() async {
    let source = FakeVolumeSource()
    var updates = KindleVolumeMonitor(source: source).volumes().makeAsyncIterator()
    #expect(await updates.next() == [])

    source.mount(other)
    source.unmount(other)
    source.mount(kindle)

    #expect(await updates.next() == [expected(kindle)])
  }

  @Test func ordersKindlesWithTheSameNameByMountPoint() throws {
    let second = MountedVolume(url: try makeVolumeRoot(), name: "Kindle")
    let ascending = [kindle, second].sorted { $0.url.path < $1.url.path }

    let kindles = KindleVolumeMonitor.kindles(in: ascending.reversed())

    #expect(kindles.map(\.mountURL) == ascending.map(\.url))
  }

  @Test func givesEveryListenerItsOwnStream() async {
    let source = FakeVolumeSource()
    let monitor = KindleVolumeMonitor(source: source)
    var first = monitor.volumes().makeAsyncIterator()
    var second = monitor.volumes().makeAsyncIterator()
    #expect(await first.next() == [])
    #expect(await second.next() == [])

    source.mount(kindle)

    #expect(await first.next() == [expected(kindle)])
    #expect(await second.next() == [expected(kindle)])
  }

  @Test func stopsListeningWhenNobodyListens() async {
    let source = FakeVolumeSource()
    let monitor = KindleVolumeMonitor(source: source)

    let listener = Task {
      for await _ in monitor.volumes() {}
    }
    #expect(await eventually { source.subscriberCount == 1 })
    listener.cancel()

    #expect(await eventually { source.subscriberCount == 0 })
  }
}
