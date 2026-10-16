import Darwin
import Foundation

package struct FileStatus: Hashable, Sendable {
  package let isDirectory: Bool
  /// An iCloud placeholder whose contents aren't on this Mac.
  package let isDataless: Bool
  package let size: Int64

  package init(isDirectory: Bool, isDataless: Bool, size: Int64) {
    self.isDirectory = isDirectory
    self.isDataless = isDataless
    self.size = size
  }

  package init(_ info: stat) {
    self.init(
      isDirectory: info.st_mode & S_IFMT == S_IFDIR,
      isDataless: info.st_flags & UInt32(SF_DATALESS) != 0,
      size: Int64(info.st_size)
    )
  }
}

package protocol FileProbe: Sendable {
  /// Nil when nothing is at `url`.
  func status(of url: URL) -> FileStatus?
}

/// Reads file metadata without downloading iCloud placeholders.
package struct DatalessAwareFileProbe: FileProbe {
  package init() {}

  package func status(of url: URL) -> FileStatus? {
    let policy = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
    let previous = getiopolicy_np(policy, IOPOL_SCOPE_THREAD)
    setiopolicy_np(policy, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    defer {
      if previous >= 0 { setiopolicy_np(policy, IOPOL_SCOPE_THREAD, previous) }
    }
    var info = stat()
    guard stat(url.path(percentEncoded: false), &info) == 0 else { return nil }
    return FileStatus(info)
  }
}
