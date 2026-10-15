import Foundation
import SendleDomain
import SendlePersistence
import SendleTestSupport
import Testing

struct JSONSettingsStoreTests {
  let directory: URL
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  init() throws {
    directory = try makeTemporaryDirectory()
  }

  @Test func startsWithDefaultsWhenNothingIsSaved() async {
    let store = JSONSettingsStore(directory: directory)
    #expect(await store.load() == .defaults)
  }

  @Test func savesAndLoadsSettings() async throws {
    let settings = AppSettings(email: .fixture, layout: .list, activeDestination: .usb)
    try await JSONSettingsStore(directory: directory).save(settings)

    #expect(await JSONSettingsStore(directory: directory).load() == settings)
  }

  @Test func createsTheDataFolderOnFirstSave() async throws {
    let nested = directory.appending(path: "not/yet/there")
    try await JSONSettingsStore(directory: nested).save(.defaults)

    #expect(FileManager.default.fileExists(atPath: nested.appending(path: "settings.json").path()))
  }

  @Test func keepsACorruptFileAsideAndStartsFresh() async throws {
    let file = directory.appending(path: "settings.json")
    try Data("{ not json".utf8).write(to: file)
    let now = now

    let settings = await JSONSettingsStore(directory: directory, now: { now }).load()

    #expect(settings == .defaults)
    #expect(!FileManager.default.fileExists(atPath: file.path()))
    let kept = directory.appending(path: "settings.corrupt-1800000000.json")
    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
  }

  @Test func reportsAFailedWrite() async throws {
    let blocker = directory.appending(path: "blocker")
    try Data().write(to: blocker)
    let store = JSONSettingsStore(directory: blocker.appending(path: "inside"))

    await #expect(throws: StorageError.self) { try await store.save(.defaults) }
  }
}

struct JSONSendHistoryStoreTests {
  let directory: URL

  init() throws {
    directory = try makeTemporaryDirectory()
  }

  func record(_ id: String, at seconds: TimeInterval = 1_800_000_000) -> SendRecord {
    SendRecord(
      bookID: BookID(rawValue: id), destination: .email,
      date: Date(timeIntervalSince1970: seconds), outcome: .sent)
  }

  @Test func startsEmpty() async {
    #expect(await JSONSendHistoryStore(directory: directory).records().isEmpty)
  }

  @Test func appendsInOrderAndSurvivesARestart() async throws {
    try await JSONSendHistoryStore(directory: directory).append(record("a"))
    try await JSONSendHistoryStore(directory: directory).append(record("b"))

    let ids = await JSONSendHistoryStore(directory: directory).records().map(\.bookID.rawValue)
    #expect(ids == ["a", "b"])
  }

  @Test func keepsOnlyTheNewestRecords() async throws {
    let store = JSONSendHistoryStore(directory: directory, limit: 2)
    for id in ["a", "b", "c"] {
      try await store.append(record(id))
    }

    #expect(await store.records().map(\.bookID.rawValue) == ["b", "c"])
  }

  @Test func keepsACorruptFileAsideAndStartsEmpty() async throws {
    try Data("[{".utf8).write(to: directory.appending(path: "history.json"))
    let store = JSONSendHistoryStore(directory: directory, now: { Date(timeIntervalSince1970: 5) })

    #expect(await store.records().isEmpty)
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "history.corrupt-5.json").path()))
  }
}
