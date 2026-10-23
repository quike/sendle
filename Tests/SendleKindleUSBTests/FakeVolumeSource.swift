import Foundation
import SendleKindleUSB
import SendleTestSupport
import os

final class FakeVolumeSource: VolumeSource {
  private let mounted: OSAllocatedUnfairLock<[MountedVolume]>
  private let feed = Broadcast<Void>()

  init(_ volumes: [MountedVolume] = []) {
    mounted = OSAllocatedUnfairLock(initialState: volumes)
  }

  var subscriberCount: Int { feed.subscriberCount }

  func mountedVolumes() -> [MountedVolume] {
    mounted.withLock { $0 }
  }

  func changes() -> AsyncStream<Void> {
    feed.stream()
  }

  func mount(_ volume: MountedVolume) {
    mounted.withLock { $0.append(volume) }
    feed.send(())
  }

  func unmount(_ volume: MountedVolume) {
    mounted.withLock { $0.removeAll { $0 == volume } }
    feed.send(())
  }
}
