import AppKit

/// The volumes Finder shows, and NSWorkspace's news of mounts, unmounts and renames.
struct WorkspaceVolumes: VolumeSource {
  private static let keys: [URLResourceKey] = [
    .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
  ]

  /// Network shares and the startup disk are never Kindles, so they aren't looked into.
  func mountedVolumes() -> [MountedVolume] {
    let urls =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Self.keys, options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
        values.volumeIsLocal == true, values.volumeIsRootFileSystem != true
      else { return nil }
      return MountedVolume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent)
    }
  }

  func changes() -> AsyncStream<Void> {
    AsyncStream { continuation in
      let center = NSWorkspace.shared.notificationCenter
      let names = [
        NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
        NSWorkspace.didRenameVolumeNotification,
      ]
      let observers = Observers(
        center: center,
        tokens: names.map {
          center.addObserver(forName: $0, object: nil, queue: nil) { _ in continuation.yield() }
        })
      continuation.onTermination = { _ in observers.remove() }
    }
  }
}

/// NotificationCenter's tokens, held until the stream that needs them ends.
private final class Observers: @unchecked Sendable {
  private let center: NotificationCenter
  private let tokens: [any NSObjectProtocol]

  init(center: NotificationCenter, tokens: [any NSObjectProtocol]) {
    self.center = center
    self.tokens = tokens
  }

  func remove() {
    tokens.forEach(center.removeObserver)
  }
}
