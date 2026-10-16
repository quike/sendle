import Foundation
import SendleAppleBooks
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LibraryWatcherTests {
  let folder: URL
  let database: URL
  let changes = Recorder<Date>()

  init() throws {
    folder = try makeTemporaryDirectory()
    database = folder.appending(path: "BKLibrary-1-1.sqlite")
    try Data("v1".utf8).write(to: database)
  }

  @Test func reportsAWriteToALibraryFile() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())
    defer { watcher.stop() }

    try append("v2", to: database)

    try await waitForChanges(count: 1)
  }

  @Test func reportsANewLibraryFile() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())
    defer { watcher.stop() }

    try Data("wal".utf8).write(to: folder.appending(path: "BKLibrary-1-1.sqlite-wal"))

    try await waitForChanges(count: 1)
  }

  @Test func watchesALibraryFileCreatedAfterStarting() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())
    defer { watcher.stop() }
    let wal = folder.appending(path: "BKLibrary-1-1.sqlite-wal")
    try Data("wal".utf8).write(to: wal)
    try await waitForChanges(count: 1)
    try await Task.sleep(for: .milliseconds(200))
    let baseline = await changes.values.count

    try append("frame", to: wal)

    try await waitForChanges(count: baseline + 1)
  }

  @Test func keepsWatchingAFileThatWasReplaced() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())
    defer { watcher.stop() }

    try Data("v2".utf8).write(to: database, options: .atomic)
    try await waitForChanges(count: 1)
    try append("v3", to: database)

    try await waitForChanges(count: 2)
  }

  @Test func reportsABurstOfWritesOnce() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(500))
    #expect(watcher.start())
    defer { watcher.stop() }

    for version in 2...6 { try append("v\(version)", to: database) }
    try await waitForChanges(count: 1)
    try await Task.sleep(for: .seconds(1))

    #expect(await changes.values.count == 1)
  }

  @Test func ignoresOtherFiles() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())
    let shm = folder.appending(path: "BKLibrary-1-1.sqlite-shm")
    try Data("shm".utf8).write(to: shm)
    try await waitForChanges(count: 1)  // the folder itself changed: a new entry

    try append("more", to: shm)
    try await Task.sleep(for: .milliseconds(500))
    watcher.stop()

    #expect(await changes.values.count == 1)
  }

  @Test func reportsNothingAfterStopping() async throws {
    let watcher = makeWatcher(batchDelay: .milliseconds(50))
    #expect(watcher.start())

    watcher.stop()
    try append("v2", to: database)
    try await Task.sleep(for: .milliseconds(500))

    #expect(await changes.values.isEmpty)
  }

  @Test func cannotWatchAMissingFolder() {
    let watcher = LibraryWatcher(
      directory: folder.appending(path: "missing"), isLibraryFile: { _ in true },
      batchDelay: .milliseconds(50), onChange: {})

    #expect(!watcher.start())
  }

  private func makeWatcher(batchDelay: DispatchTimeInterval) -> LibraryWatcher {
    let changes = changes
    return LibraryWatcher(
      directory: folder,
      isLibraryFile: { $0.hasPrefix("BKLibrary-") && !$0.hasSuffix("-shm") },
      batchDelay: batchDelay
    ) {
      Task { await changes.record(Date()) }
    }
  }

  private func waitForChanges(count: Int) async throws {
    while await changes.values.count < count {
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }
}
