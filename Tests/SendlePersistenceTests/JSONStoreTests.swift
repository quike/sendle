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
    try await JSONSettingsStore(directory: directory).update { $0 = settings }

    #expect(await JSONSettingsStore(directory: directory).load() == settings)
  }

  @Test func logsASaveThatFailed() async throws {
    let log = FakeActivityLog()
    let blocked = directory.appending(path: "file-not-folder")
    try Data().write(to: blocked)

    await #expect(throws: StorageError.self) {
      try await JSONSettingsStore(directory: blocked, log: log).update { $0.layout = .list }
    }

    #expect(log.summary.contains { $0.hasPrefix("error APP Couldn't save settings.json: ") })
  }

  @Test func createsTheDataFolderOnFirstSave() async throws {
    let nested = directory.appending(path: "not/yet/there")
    try await JSONSettingsStore(directory: nested).update { $0 = .defaults }

    #expect(FileManager.default.fileExists(atPath: nested.appending(path: "settings.json").path()))
  }

  @Test func keepsACorruptFileAsideAndStartsFresh() async throws {
    let file = directory.appending(path: "settings.json")
    try Data("{ not json".utf8).write(to: file)
    let now = now
    let log = FakeActivityLog()

    let settings = await JSONSettingsStore(directory: directory, now: { now }, log: log).load()

    #expect(
      log.summary == [
        "warning APP settings.json couldn't be read, so Sendle moved it to "
          + "settings.corrupt-1800000000.json"
      ])
    #expect(settings == .defaults)
    #expect(!FileManager.default.fileExists(atPath: file.path()))
    let kept = directory.appending(path: "settings.corrupt-1800000000.json")
    #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
  }

  @Test func tellsOnceWhereAnUnreadableFileWasMoved() async throws {
    try Data("{ not json".utf8).write(to: directory.appending(path: "settings.json"))
    let now = now
    let store = JSONSettingsStore(directory: directory, now: { now })
    #expect(await store.takeQuarantinedFile() == nil)

    _ = await store.load()

    let kept = await store.takeQuarantinedFile()
    #expect(kept?.lastPathComponent == "settings.corrupt-1800000000.json")
    #expect(await store.takeQuarantinedFile() == nil)
  }

  @Test func keepsAnUnreadableFileAsideInsteadOfOverwritingIt() async throws {
    let file = directory.appending(path: "settings.json")
    try Data(#"{"layout": "list"}"#.utf8).write(to: file)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))
    let now = now
    let store = JSONSettingsStore(directory: directory, now: { now })

    #expect(await store.load() == .defaults)
    try await store.update { $0 = .defaults }

    let kept = directory.appending(path: "settings.corrupt-1800000000.json")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: kept.path(percentEncoded: false))
    #expect(try String(contentsOf: kept, encoding: .utf8) == #"{"layout": "list"}"#)
  }

  @Test func updateReturnsTheSettingsBeforeTheChange() async throws {
    let store = JSONSettingsStore(directory: directory)
    try await store.update { $0.layout = .list }

    let previous = try await store.update { $0.layout = .shelf }

    #expect(previous.layout == .list)
    #expect(await store.load().layout == .shelf)
  }

  @Test func updatesFromDifferentWritersAllSurvive() async throws {
    let store = JSONSettingsStore(directory: directory)

    async let layout = store.update { $0.layout = .shelf }
    async let email = store.update { $0.email = .fixture }
    _ = try await (layout, email)

    let settings = await store.load()
    #expect(settings.layout == .shelf)
    #expect(settings.email == .fixture)
  }

  @Test func readsTheSettingsFormatThisVersionWrites() async throws {
    let json = """
      {
        "activeDestination" : "usb",
        "email" : {
          "kindleAddress" : "reader@kindle.com",
          "provider" : "gmail",
          "senderAddress" : "me@gmail.com",
          "server" : { "host" : "smtp.gmail.com", "port" : 465, "security" : "implicitTLS" }
        },
        "layout" : "shelf"
      }
      """
    try Data(json.utf8).write(to: directory.appending(path: "settings.json"))

    let settings = await JSONSettingsStore(directory: directory).load()

    #expect(settings == AppSettings(email: .fixture, layout: .shelf, activeDestination: .usb))
  }

  @Test func reportsAFailedWrite() async throws {
    let blocker = directory.appending(path: "blocker")
    try Data().write(to: blocker)
    let store = JSONSettingsStore(directory: blocker.appending(path: "inside"))

    await #expect(throws: StorageError.self) { try await store.update { $0 = .defaults } }
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

  @Test func keepsEveryCorruptFileEvenWithinTheSameSecond() async throws {
    let file = directory.appending(path: "history.json")
    let store = JSONSendHistoryStore(directory: directory, now: { Date(timeIntervalSince1970: 5) })

    try Data("first".utf8).write(to: file)
    #expect(await store.records().isEmpty)
    try Data("second".utf8).write(to: file)
    #expect(await store.records().isEmpty)

    let kept = try FileManager.default
      .contentsOfDirectory(atPath: directory.path(percentEncoded: false))
      .filter { $0.hasPrefix("history.corrupt-5") }
    #expect(kept.count == 2)
  }

  @Test func readsTheHistoryFormatThisVersionWrites() async throws {
    let json = """
      [ { "bookID" : "book-1", "date" : "2027-01-15T08:00:00Z", "destination" : "email",
          "outcome" : "sent" } ]
      """
    try Data(json.utf8).write(to: directory.appending(path: "history.json"))

    #expect(await JSONSendHistoryStore(directory: directory).records() == [record("book-1")])
  }
}
