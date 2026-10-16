import Foundation
import SendleDomain
import SendleTestSupport
import Testing

struct SendBooksTests {
  struct Harness {
    let channel: FakeDeliveryChannel
    let channels: FakeDeliveryChannelFactory
    let preparer: FakeEPUBPreparer
    let converter: FakeFormatConverter
    let staging: FakeStagingArea
    let history: InMemorySendHistoryStore
    let sleeps = Recorder<Duration>()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init(
      channel: FakeDeliveryChannel = FakeDeliveryChannel(),
      channelFailure: SendFailure? = nil,
      preparer: FakeEPUBPreparer = FakeEPUBPreparer(),
      converter: FakeFormatConverter = FakeFormatConverter(),
      staging: FakeStagingArea = FakeStagingArea(),
      history: InMemorySendHistoryStore = InMemorySendHistoryStore()
    ) {
      self.channel = channel
      self.channels = FakeDeliveryChannelFactory(channel: channel, failure: channelFailure)
      self.preparer = preparer
      self.converter = converter
      self.staging = staging
      self.history = history
    }

    var sendBooks: SendBooks {
      let sleeps = sleeps
      let now = now
      return SendBooks(
        channels: channels, preparer: preparer, converter: converter, staging: staging,
        history: history, now: { now }, retryDelay: .seconds(2),
        sleep: { await sleeps.record($0) })
    }

    func send(_ books: [Book], to destination: Destination) async -> [SendEvent] {
      let events = Recorder<SendEvent>()
      await sendBooks(books, to: destination) { await events.record($0) }
      return await events.values
    }
  }

  let email = Destination.email(.fixture)

  @Test func emailsAnEPUBAfterPreparingIt() async {
    let harness = Harness(preparer: FakeEPUBPreparer(fixes: [.addedLanguage]))
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(
      events == [
        .preparing(book.id),
        .uploading(book.id, fraction: 0.5),
        .uploading(book.id, fraction: 1),
        .sent(book.id, fixes: [.addedLanguage]),
      ])
    #expect(harness.channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(harness.channel.deliveries.map(\.file.format) == [.epub])
    #expect(harness.channels.requestedDestinations == [email])
    #expect(
      await harness.history.records() == [
        SendRecord(bookID: book.id, destination: .email, date: harness.now, outcome: .sent)
      ])
  }

  @Test func cleansUpTheStagingFolderAfterEverySend() async {
    let harness = Harness()

    _ = await harness.send([.fixture(id: "a"), .fixture(id: "b")], to: email)

    let staging = harness.staging.snapshot
    #expect(staging.made.count == 2)
    #expect(staging.removed == staging.made)
  }

  @Test func emailsAPDFWithoutTouchingIt() async {
    let harness = Harness()
    let book = Book.fixture(format: .pdf)

    _ = await harness.send([book], to: email)

    #expect(harness.preparer.preparedIDs.isEmpty)
    #expect(
      harness.channel.deliveries.map(\.file) == [PreparedFile(url: book.fileURL, format: .pdf)])
  }

  @Test func convertsEPUBsForUSBAndKeepsTheFixes() async {
    let harness = Harness(preparer: FakeEPUBPreparer(fixes: [.addedXMLDeclaration]))
    let book = Book.fixture()

    let events = await harness.send([book], to: .usb(.fixture()))

    #expect(harness.converter.convertedFiles.map(\.format) == [.epub])
    #expect(harness.channel.deliveries.map(\.file.format) == [.azw3])
    #expect(events.last == .sent(book.id, fixes: [.addedXMLDeclaration]))
  }

  @Test func reportsABlockedBookWithoutStartingWork() async {
    let harness = Harness()
    let book = Book.fixture(availability: .protected)

    let events = await harness.send([book], to: email)

    #expect(events == [.failed(book.id, .protected)])
    #expect(harness.staging.snapshot.made.isEmpty)
    #expect(await harness.history.records().isEmpty)
  }

  @Test func carriesOnWithTheNextBookAfterAFailure() async {
    let harness = Harness()
    let blocked = Book.fixture(id: "blocked", availability: .missing)
    let fine = Book.fixture(id: "fine")

    let events = await harness.send([blocked, fine], to: email)

    #expect(events.first == .failed(blocked.id, .missing))
    #expect(events.last == .sent(fine.id, fixes: []))
  }

  @Test func retriesOnceAfterAConnectionFailure() async {
    let channel = FakeDeliveryChannel(.fail(.connectionFailed(host: "smtp.gmail.com")), .succeed)
    let harness = Harness(channel: channel)
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events.last == .sent(book.id, fixes: []))
    #expect(channel.deliveries.count == 2)
    #expect(await harness.sleeps.values == [.seconds(2)])
  }

  @Test func givesUpAfterTheSecondConnectionFailure() async {
    let failure = SendFailure.connectionFailed(host: "smtp.gmail.com")
    let channel = FakeDeliveryChannel(.fail(failure))
    let harness = Harness(channel: channel)
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events.last == .failed(book.id, failure))
    #expect(channel.deliveries.count == 2)
    #expect(await harness.history.records().map(\.outcome) == [.failed])
  }

  @Test func neverRetriesARejectedPassword() async {
    let channel = FakeDeliveryChannel(.fail(.authenticationFailed(.gmail)))
    let harness = Harness(channel: channel)

    let events = await harness.send([.fixture()], to: email)

    #expect(events.last == .failed(BookID(rawValue: "book-1"), .authenticationFailed(.gmail)))
    #expect(channel.deliveries.count == 1)
    #expect(await harness.sleeps.values.isEmpty)
  }

  @Test func reportsPreparationFailuresAndStillCleansUp() async {
    let harness = Harness(preparer: FakeEPUBPreparer(failure: .invalidBook("no OPF")))
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events == [.preparing(book.id), .failed(book.id, .invalidBook("no OPF"))])
    #expect(harness.staging.snapshot.removed.count == 1)
    #expect(harness.channel.deliveries.isEmpty)
  }

  @Test func reportsMissingEmailSetupFromTheFactory() async {
    let harness = Harness(channelFailure: .notConfigured)
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events.last == .failed(book.id, .notConfigured))
  }

  @Test func reportsAStagingFailure() async {
    let harness = Harness(staging: FakeStagingArea(failure: .localStorage("disk full")))
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events.last == .failed(book.id, .localStorage("disk full")))
  }

  @Test func aHistoryWriteFailureDoesNotFailTheSend() async {
    let harness = Harness(history: InMemorySendHistoryStore(failure: .writeFailed("read-only")))
    let book = Book.fixture()

    let events = await harness.send([book], to: email)

    #expect(events.last == .sent(book.id, fixes: []))
  }

  @Test func cancellingStopsTheCurrentAndRemainingBooks() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let harness = Harness(channel: channel)
    let first = Book.fixture(id: "first")
    let second = Book.fixture(id: "second")
    let events = Recorder<SendEvent>()
    let sendBooks = harness.sendBooks

    let task = Task {
      await sendBooks([first, second], to: email) { await events.record($0) }
    }
    await channel.waitUntilDeliveryStarts()
    task.cancel()
    await task.value

    #expect(
      await events.values == [
        .preparing(first.id),
        .failed(first.id, .cancelled),
        .failed(second.id, .cancelled),
      ])
    #expect(channel.deliveries.count == 1)
    #expect(await harness.history.records().isEmpty)
    #expect(harness.staging.snapshot.removed.count == 1)
  }

  @Test func aCancelAfterTheServerHadTheWholeBookStaysUnconfirmed() async {
    let unconfirmed = SendFailure.unconfirmed(host: "smtp.gmail.com")
    let channel = FakeDeliveryChannel(.hangThenFail(unconfirmed))
    let harness = Harness(channel: channel)
    let first = Book.fixture(id: "first")
    let second = Book.fixture(id: "second")
    let events = Recorder<SendEvent>()
    let sendBooks = harness.sendBooks

    let task = Task {
      await sendBooks([first, second], to: email) { await events.record($0) }
    }
    await channel.waitUntilDeliveryStarts()
    task.cancel()
    await task.value

    #expect(
      await events.values == [
        .preparing(first.id),
        .failed(first.id, unconfirmed),
        .failed(second.id, .cancelled),
      ])
    #expect(channel.deliveries.count == 1)
    #expect(await harness.history.records().map(\.bookID) == [first.id])
    #expect(await harness.history.records().map(\.outcome) == [.failed])
  }

  @Test func cancellingDuringTheRetryDelaySkipsTheSecondAttempt() async {
    let channel = FakeDeliveryChannel(.fail(.connectionFailed(host: "smtp.gmail.com")), .succeed)
    let harness = Harness(channel: channel)
    let waiting = Signal()
    let book = Book.fixture()
    let events = Recorder<SendEvent>()
    let sendBooks = SendBooks(
      channels: harness.channels, preparer: harness.preparer, converter: harness.converter,
      staging: harness.staging, history: harness.history,
      sleep: { _ in
        await waiting.fire()
        try? await Task.sleep(for: .seconds(3_600))
      })

    let task = Task {
      await sendBooks([book], to: email) { await events.record($0) }
    }
    await waiting.wait()
    task.cancel()
    await task.value

    #expect(await events.values.last == .failed(book.id, .cancelled))
    #expect(channel.deliveries.count == 1)
    #expect(await harness.history.records().isEmpty)
  }

  @Test func theDefaultClockAndSleepWork() async throws {
    let channel = FakeDeliveryChannel(.fail(.connectionFailed(host: "smtp.gmail.com")), .succeed)
    let history = InMemorySendHistoryStore()
    let sendBooks = SendBooks(
      channels: FakeDeliveryChannelFactory(channel: channel), preparer: FakeEPUBPreparer(),
      converter: FakeFormatConverter(), staging: FakeStagingArea(), history: history,
      retryDelay: .zero)
    let before = Date()

    await sendBooks([.fixture()], to: email) { _ in }

    #expect(channel.deliveries.count == 2)
    #expect(try #require(await history.records().first).date >= before)
  }
}
