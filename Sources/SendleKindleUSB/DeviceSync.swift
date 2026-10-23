import Darwin
import Foundation

/// Pushes writes past the Mac's caches and the Kindle's own, so a Kindle unplugged without Eject
/// keeps them. `fsync` alone leaves FAT's folder entry, which holds a file's size, for later: a
/// Kindle unplugged then repairs the file down to the clusters it got.
enum DeviceSync {
  @discardableResult
  static func flush(_ descriptor: Int32) -> Bool {
    fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0
  }

  static func flush(_ url: URL) {
    let descriptor = open(url.path, O_RDONLY)
    guard descriptor >= 0 else { return }
    flush(descriptor)
    close(descriptor)
  }
}
