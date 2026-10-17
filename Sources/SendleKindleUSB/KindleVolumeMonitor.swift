import Foundation
import SendleDomain

/// A mounted volume: where its root is and what Finder calls it.
package struct MountedVolume: Hashable, Sendable {
  package let url: URL
  package let name: String

  package init(url: URL, name: String) {
    self.url = url
    self.name = name
  }
}

package protocol VolumeSource: Sendable {
  func mountedVolumes() -> [MountedVolume]
  /// An independent stream per call that emits whenever a volume is mounted, unmounted or renamed.
  func changes() -> AsyncStream<Void>
}

/// Follows drive-mounted Kindles: the ones plugged in now, then every change to that list.
public struct KindleVolumeMonitor: DestinationMonitor {
  private let source: any VolumeSource

  public init() {
    self.init(source: WorkspaceVolumes())
  }

  package init(source: any VolumeSource) {
    self.source = source
  }

  public func volumes() -> AsyncStream<[KindleVolume]> {
    // Listening before the first look means no mount can fall between the two.
    let changes = source.changes()
    let source = source
    return AsyncStream { continuation in
      let task = Task {
        var last = Self.kindles(in: source.mountedVolumes())
        continuation.yield(last)
        for await _ in changes {
          let current = Self.kindles(in: source.mountedVolumes())
          guard current != last else { continue }
          last = current
          continuation.yield(current)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The Kindles among `volumes`, by name and then mount point, so the order never flips.
  package static func kindles(in volumes: [MountedVolume]) -> [KindleVolume] {
    volumes.filter { KindleVolumeDetector.isKindle(root: $0.url, name: $0.name) }
      .map {
        KindleVolume(id: $0.url.path(percentEncoded: false), name: $0.name, mountURL: $0.url)
      }
      .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
  }
}
