import Foundation
import SendleDomain
import SendlePersistence
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MemoryActivityLogTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func keepsTheLinesInOrderWithTheirDetails() {
    let now = now
    let log = MemoryActivityLog(now: { now })

    log.heading(.book(BookID(rawValue: "b1")), .mail, "Moby-Dick · reader@kindle.com")
    log.debug(.mail, "C: EHLO [127.0.0.1]")
    log.error(.mail, "S: 553 5.7.1 Sender address rejected")

    #expect(
      log.entries() == [
        LogEntry(
          id: 1, date: now, level: .info, area: .mail, message: "Moby-Dick · reader@kindle.com",
          heading: .book(BookID(rawValue: "b1"))),
        LogEntry(id: 2, date: now, level: .debug, area: .mail, message: "C: EHLO [127.0.0.1]"),
        LogEntry(
          id: 3, date: now, level: .error, area: .mail,
          message: "S: 553 5.7.1 Sender address rejected"),
      ])
  }

  @Test func keepsOnlyTheNewestLines() {
    let log = MemoryActivityLog(capacity: 3)

    for line in 1...5 { log.info(.app, "line \(line)") }

    #expect(log.entries().map(\.message) == ["line 3", "line 4", "line 5"])
    #expect(log.entries().map(\.id) == [3, 4, 5])
  }

  @Test func holdsFiveThousandLinesByDefault() {
    let log = MemoryActivityLog()

    for line in 1...5_001 { log.debug(.usb, "\(line)") }

    #expect(log.entries().count == 5_000)
    #expect(log.entries().first?.message == "2")
  }

  @Test func clearingKeepsCountingUp() {
    let log = MemoryActivityLog()
    log.info(.app, "before")

    log.clear()
    log.info(.app, "after")

    #expect(log.entries().map(\.id) == [2])
  }

  @Test func tellsEveryListenerAboutEachChange() async {
    let log = MemoryActivityLog()
    let first = log.changes()
    let second = log.changes()

    log.info(.library, "Read 2 books")

    var firstChanges = first.makeAsyncIterator()
    var secondChanges = second.makeAsyncIterator()
    #expect(await firstChanges.next() != nil)
    #expect(await secondChanges.next() != nil)
  }
}
