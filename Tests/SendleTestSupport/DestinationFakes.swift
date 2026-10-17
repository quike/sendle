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

public final class FakeKindleEjector: KindleEjector {
  private let log = OSAllocatedUnfairLock<[KindleVolume]>(initialState: [])
  private let failure = OSAllocatedUnfairLock<EjectError?>(initialState: nil)

  public init() {}

  public var ejected: [KindleVolume] { log.withLock { $0 } }

  /// Every later eject fails with `error`.
  public func fail(with error: EjectError) {
    failure.withLock { $0 = error }
  }

  public func eject(_ volume: KindleVolume) async throws(EjectError) {
    log.withLock { $0.append(volume) }
    if let error = failure.withLock({ $0 }) { throw error }
  }
}
