import SendleDomain
import os

public final class FakeDestinationMonitor: DestinationMonitor {
  private let current: OSAllocatedUnfairLock<[KindleVolume]>
  private let feed = Broadcast<[KindleVolume]>()

  public init(_ volumes: [KindleVolume] = []) {
    current = OSAllocatedUnfairLock(initialState: volumes)
  }

  public var subscriberCount: Int { feed.subscriberCount }

  /// Each stream starts with the Kindles plugged in now, as the port promises. Holding the lock
  /// while subscribing means an update can't fall between the first value and the next.
  public func volumes() -> AsyncStream<[KindleVolume]> {
    current.withLock { feed.stream(startingWith: $0) }
  }

  public func update(_ volumes: [KindleVolume]) {
    current.withLock {
      $0 = volumes
      feed.send(volumes)
    }
  }

  public func finish() {
    feed.finish()
  }
}
