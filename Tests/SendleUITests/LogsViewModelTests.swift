import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LogsViewModelTests {
  let log = FakeActivityLog()
  let moby = BookID(rawValue: "moby")
  let utc = TimeZone(identifier: "UTC") ?? .current

  func makeModel() -> LogsViewModel {
    let model = LogsViewModel(feed: log, timeZone: utc)
    model.refresh()
    return model
  }

  func messages(_ model: LogsViewModel) -> [String] {
    model.visible.map(\.message)
  }

  func readingEntry(_ model: LogsViewModel) throws -> LogEntry {
    try #require(model.visible.first { $0.message.hasPrefix("Reading") })
  }

  func recordASend() {
    log.heading(.book(moby), .mail, "Moby-Dick · reader@kindle.com")
    log.debug(.mail, "C: EHLO [127.0.0.1]")
    log.error(.mail, "S: 553 5.7.1 Sender address rejected")
    log.heading(.book(BookID(rawValue: "frank")), .usb, "Frankenstein · Paperwhite (USB)")
    log.info(.boko, "Running boko convert")
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    log.info(.library, "Read 2 books")
    log.warning(.app, "settings.json couldn't be read")
  }

  @Test func showsEveryLineByDefault() {
    recordASend()

    #expect(makeModel().visible.count == 8)
  }

  @Test func filtersByArea() {
    recordASend()
    let model = makeModel()

    model.area = .usb
    #expect(
      messages(model) == [
        "Frankenstein · Paperwhite (USB)", "Running boko convert",
        "Reading Frankenstein.epub\nWriting AZW3\nDone",
      ])

    model.area = .library
    #expect(messages(model) == ["Read 2 books"])

    model.area = .app
    #expect(messages(model) == ["settings.json couldn't be read"])
  }

  @Test func hidesTheLevelsTurnedOff() {
    recordASend()
    let model = makeModel()

    model.toggle(.debug)
    model.toggle(.info)

    #expect(model.isShowing(.warning))
    #expect(!model.isShowing(.debug))
    #expect(
      messages(model) == [
        "Moby-Dick · reader@kindle.com", "S: 553 5.7.1 Sender address rejected",
        "settings.json couldn't be read",
      ])
  }

  @Test func searchKeepsLinesWithEveryWordWhateverTheirCaseAndAccents() {
    recordASend()
    let model = makeModel()

    model.query = "sender REJECTED"
    #expect(
      messages(model) == ["Moby-Dick · reader@kindle.com", "S: 553 5.7.1 Sender address rejected"])

    model.query = "écrit azw3"
    #expect(messages(model).isEmpty)
  }

  @Test func searchIgnoresAccents() {
    log.info(.app, "Saved Café.epub")
    log.info(.app, "Saved Moby-Dick.epub")
    let model = makeModel()

    model.query = "cafe"

    #expect(messages(model) == ["Saved Café.epub"])
  }

  @Test func aHeadingStaysAboveLinesThatCameAfterItFromElsewhere() {
    log.heading(.book(moby), .mail, "Moby-Dick · reader@kindle.com")
    log.debug(.mail, "Plan: deliver it")
    log.info(.library, "Read 2 books")
    log.info(.mail, "Sent")
    let model = makeModel()

    model.toggle(.debug)

    #expect(messages(model) == ["Moby-Dick · reader@kindle.com", "Read 2 books", "Sent"])
  }

  @Test func aHeadingShowsOnlyWithSomethingUnderIt() {
    recordASend()
    let model = makeModel()

    model.query = "boko"

    #expect(messages(model) == ["Frankenstein · Paperwhite (USB)", "Running boko convert"])
  }

  @Test func foldsLongEntriesUntilOpened() throws {
    recordASend()
    let model = makeModel()
    let long = try #require(model.visible.first { $0.message.hasPrefix("Reading") })

    #expect(LogsViewModel.extraLines(in: long) == 2)
    #expect(!model.isExpanded(long))
    model.toggleExpanded(long)
    #expect(model.isExpanded(long))
    model.toggleExpanded(long)
    #expect(!model.isExpanded(long))
  }

  @Test func highlightsTheSearchedWords() {
    let model = makeModel()
    let line = "SMTP auth accepted"

    model.query = "smtp auth"

    #expect(model.highlights(in: line).map { String(line[$0]) } == ["SMTP", "auth"])
  }

  @Test func highlightsNothingWithoutASearch() {
    #expect(makeModel().highlights(in: "SMTP auth accepted").isEmpty)
  }

  @Test func searchOpensAnEntryMatchedPastItsFirstLine() throws {
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    log.debug(.boko, "Writing AZW3\nDone")
    let model = makeModel()
    let past = try readingEntry(model)
    let firstLineOnly = try #require(model.visible.last)

    #expect(!model.isExpanded(past))

    model.query = "azw3"
    #expect(model.isExpanded(past))
    #expect(!model.isExpanded(firstLineOnly))

    model.query = ""
    #expect(!model.isExpanded(past))
  }

  @Test func closingASearchOpenedEntryLastsUntilTheSearchChanges() throws {
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    let model = makeModel()
    let entry = try readingEntry(model)
    model.query = "azw3"

    model.toggleExpanded(entry)
    #expect(!model.isExpanded(entry))

    log.info(.library, "Read 2 books")
    model.refresh()
    model.area = .usb
    model.area = .all
    #expect(!model.isExpanded(entry))

    model.query = "writing azw3"
    #expect(model.isExpanded(entry))
  }

  @Test func closingASearchOpenedEntryOutlastsEditsThatKeepTheWords() throws {
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    let model = makeModel()
    let entry = try readingEntry(model)
    model.query = "azw3"
    model.toggleExpanded(entry)

    model.query = "azw3 "
    #expect(!model.isExpanded(entry))

    model.query = "  azw3  "
    #expect(!model.isExpanded(entry))
  }

  @Test func anEntryOpenedByHandAndBySearchClosesInOneToggle() throws {
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    let model = makeModel()
    let entry = try readingEntry(model)
    model.toggleExpanded(entry)
    model.query = "azw3"
    #expect(model.isExpanded(entry))

    model.toggleExpanded(entry)

    #expect(!model.isExpanded(entry))
  }

  @Test func aClosedSearchOpenedEntryOpensAgainOnDemand() throws {
    log.debug(.boko, "Reading Frankenstein.epub\nWriting AZW3\nDone")
    let model = makeModel()
    let entry = try readingEntry(model)
    model.query = "azw3"
    model.toggleExpanded(entry)

    model.toggleExpanded(entry)

    #expect(model.isExpanded(entry))
  }

  @Test func copiesWhatIsShownInFull() {
    log.debug(.mail, "C: EHLO [127.0.0.1]")
    log.debug(.boko, "Reading\nWriting")
    log.info(.library, "Read 2 books")
    let model = makeModel()
    model.area = .usb

    #expect(model.copyText() == "08:00:00.000 DEBUG BOKO Reading\nWriting")

    model.area = .all
    #expect(
      model.copyText()
        == "08:00:00.000 DEBUG MAIL C: EHLO [127.0.0.1]\n08:00:00.000 DEBUG BOKO Reading\nWriting\n"
        + "08:00:00.000 INFO LIB Read 2 books")
  }

  @Test func timesShowToTheSecond() throws {
    log.info(.app, "Hello")

    #expect(makeModel().time(of: try #require(log.entries().first)) == "08:00:00")
  }

  @Test func clearingEmptiesTheLog() {
    recordASend()
    let model = makeModel()

    model.clear()

    #expect(model.visible.isEmpty)
    #expect(log.entries().isEmpty)
  }

  @Test func revealsTheLatestStoryOfABookWithEveryFilterOff() {
    recordASend()
    log.heading(.book(moby), .mail, "Moby-Dick · reader@kindle.com")
    let model = makeModel()
    model.area = .app
    model.query = "nothing"
    model.toggle(.info)

    model.reveal(.book(moby))

    #expect(model.area == .all)
    #expect(model.query.isEmpty)
    #expect(model.isShowing(.info))
    #expect(model.scrollTarget == log.entries().last?.id)
    #expect(model.revealRequests == 1)
    #expect(!model.isAtBottom)
  }

  @Test func followsNewLinesWhileOpen() async {
    let model = makeModel()
    model.start()
    defer { model.stop() }

    log.info(.usb, "Paperwhite is plugged in")

    #expect(await eventually { messages(model) == ["Paperwhite is plugged in"] })
  }

  @Test func namesLevelsAndAreasAsTheScreenShowsThem() {
    #expect(LogLevel.allCases.map(\.label) == ["DEBUG", "INFO", "WARN", "ERROR"])
    #expect(LogAreaFilter.allCases.map(\.title) == ["All", "Email", "USB", "Library", "App"])
  }
}
