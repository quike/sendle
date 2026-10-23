import Darwin
import Foundation
import SendleAppleBooks
import SendleTestSupport
import Testing

struct FileProbeTests {
  let folder: URL
  let probe = DatalessAwareFileProbe()

  init() throws {
    folder = try makeTemporaryDirectory()
  }

  @Test func describesAFile() throws {
    let file = folder.appending(path: "book.pdf")
    try Data(count: 1_234).write(to: file)

    #expect(
      probe.status(of: file) == FileStatus(isDirectory: false, isDataless: false, size: 1_234))
  }

  @Test func describesAFolder() throws {
    let epub = folder.appending(path: "book.epub", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: epub, withIntermediateDirectories: true)

    #expect(probe.status(of: epub)?.isDirectory == true)
  }

  @Test func returnsNilWhenNothingIsThere() {
    #expect(probe.status(of: folder.appending(path: "gone.epub")) == nil)
  }

  @Test func recognisesICloudPlaceholdersFromTheirFlags() {
    var info = stat()
    info.st_mode = S_IFREG | 0o644
    info.st_flags = UInt32(SF_DATALESS)
    info.st_size = 5_000

    #expect(FileStatus(info) == FileStatus(isDirectory: false, isDataless: true, size: 5_000))
  }

  @Test func restoresTheThreadsDownloadPolicy() throws {
    let before = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)

    _ = probe.status(of: folder)

    #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == before)
  }
}
