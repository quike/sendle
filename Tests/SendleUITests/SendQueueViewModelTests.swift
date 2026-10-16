import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SendQueueViewModelTests {
  let history = InMemorySendHistoryStore()
  let moby = Book.fixture(id: "a", title: "Moby-Dick")
  let dracula = Book.fixture(id: "b", title: "Dracula")
  let meditations = Book.fixture(id: "c", title: "Meditations", format: .pdf)
  let email = Destination.email(.fixture)
  let activity = ActivityLog()

  @MainActor final class ActivityLog {
    var begun = 0
    var ended = 0
  }

  func makeQueue(
    _ channel: FakeDeliveryChannel = FakeDeliveryChannel(),
    fixes: [EPUBFix] = []
  ) -> SendQueueViewModel {
    let activity = activity
    return SendQueueViewModel(
      sendBooks: SendBooks(
        channels: FakeDeliveryChannelFactory(channel: channel),
        preparer: FakeEPUBPreparer(fixes: fixes),
        converter: FakeFormatConverter(isAvailable: false), staging: FakeStagingArea(),
        history: history, retryDelay: .zero, sleep: { _ in }),
      keepAwake: {
        activity.begun += 1
        return { activity.ended += 1 }
      })
  }

  func statuses(_ queue: SendQueueViewModel) -> [QueueStatus] {
    queue.rows.map(\.status)
  }

  // MARK: Sending

  @Test func sendsEachBookAndSaysTheyAreOnTheirWay() async {
    let queue = makeQueue()

    queue.send([moby, dracula], to: email)
    await queue.waitUntilFinished()

    #expect(statuses(queue) == [.sent, .sent])
    #expect(
      queue.rows.map(\.detail)
        == Array(repeating: "Sent to Amazon · arrives in a few minutes", count: 2))
    #expect(queue.title == "Sent 2 books")
    #expect(queue.subtitle == "to Kindle email")
    #expect(queue.summary?.tone == .success)
    #expect(queue.summary?.title == "2 books are on their way")
    #expect(
      queue.summary?.message
        == "Amazon delivers them over Wi-Fi. If anything's off, Amazon emails your sender address.")
    #expect(!queue.needsAttention)
  }

  @Test func namesASingleBookOnItsWay() async {
    let queue = makeQueue()

    queue.send([moby], to: email)
    await queue.waitUntilFinished()

    #expect(queue.summary?.title == "Moby-Dick is on its way")
    #expect(queue.title == "Sent 1 book")
  }

  @Test func followsTheBookBeingSent() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)

    queue.send([moby, meditations], to: email)
    await channel.waitUntilDeliveryStarts()
    #expect(queue.rows.first?.detail == "Preparing the EPUB")
    queue.handle(.uploading(moby.id, fraction: 0.62))

    #expect(queue.isRunning)
    #expect(queue.title == "Sending 2 books")
    #expect(queue.subtitle == "to Kindle email · close the panel anytime")
    #expect(queue.rows.map(\.detail) == ["Uploading · 62%", "Waiting"])
    #expect(queue.progressLabel == "↑ 1/2")
    queue.cancel()
    await queue.waitUntilFinished()
    #expect(queue.progressLabel == nil)
  }

  @Test func showsAnUploadStartingOverAfterARetry() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)
    queue.send([moby], to: email)
    await channel.waitUntilDeliveryStarts()

    queue.handle(.uploading(moby.id, fraction: 0.8))
    queue.handle(.uploading(moby.id, fraction: 0))

    #expect(statuses(queue) == [.uploading(0)])
    #expect(queue.rows.first?.detail == "Uploading · 0%")
    queue.cancel()
    await queue.waitUntilFinished()
  }

  @Test func notesTheFixesAmazonNeeded() async {
    let queue = makeQueue(fixes: [.addedLanguage, .addedXMLDeclaration])

    queue.send([moby, meditations], to: email)
    await queue.waitUntilFinished()

    #expect(
      queue.rows.map(\.fixesNote) == ["Fixed 2 issues Amazon rejects (language, encoding)", nil])
  }

  @Test func ignoresASecondSendWhileSending() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)
    queue.send([moby], to: email)
    await channel.waitUntilDeliveryStarts()

    queue.send([dracula], to: email)

    #expect(queue.rows.map(\.id) == [moby.id])
    #expect(activity.begun == 1)
    queue.cancel()
    await queue.waitUntilFinished()
  }

  @Test func tellsWhenItIsDone() async {
    let queue = makeQueue()
    var finished = 0
    queue.onFinish = { finished += 1 }

    queue.send([moby], to: email)
    await queue.waitUntilFinished()

    #expect(finished == 1)
  }

  @Test func keepsTheMacAwakeUntilTheRunFinishes() async {
    let queue = makeQueue()
    #expect(activity.begun == 0)

    queue.send([moby, dracula], to: email)
    #expect(activity.begun == 1)
    await queue.waitUntilFinished()

    #expect(activity.begun == 1)
    #expect(activity.ended == 1)
  }

  @Test func letsTheMacSleepAgainAfterACancel() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)
    queue.send([moby], to: email)
    await channel.waitUntilDeliveryStarts()
    #expect(activity.ended == 0)

    queue.cancel()
    await queue.waitUntilFinished()

    #expect(activity.begun == 1)
    #expect(activity.ended == 1)
  }

  // MARK: Failures

  @Test func summarizesAFailureWithItsFix() async {
    let queue = makeQueue(FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))

    queue.send([moby], to: email)
    await queue.waitUntilFinished()

    let problem = ProblemPresenter.problem(for: .authenticationFailed(.gmail))
    #expect(statuses(queue) == [.failed(.authenticationFailed(.gmail))])
    #expect(queue.rows.first?.detail == problem.title)
    #expect(queue.title == "Couldn't send 1 book")
    #expect(queue.summary == Toast(tone: .failure, problem))
    #expect(queue.needsAttention)
  }

  @Test func countsWhatWasSentWhenSomeFailed() async {
    let queue = makeQueue(FakeDeliveryChannel(.succeed, .fail(.rejected("550 No"))))

    queue.send([moby, dracula], to: email)
    await queue.waitUntilFinished()

    #expect(queue.title == "Sent 1 of 2 books")
    #expect(queue.summary?.tone == .failure)
  }

  @Test func cancellingStopsTheBooksNotYetSent() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)
    queue.send([moby, dracula, meditations], to: email)
    await channel.waitUntilDeliveryStarts()

    queue.cancel()
    await queue.waitUntilFinished()

    #expect(statuses(queue) == [.cancelled, .cancelled, .cancelled])
    #expect(queue.rows.map(\.detail) == ["Cancelled", "Cancelled", "Cancelled"])
    #expect(queue.title == "Sending cancelled")
    #expect(queue.summary == nil)
    #expect(!queue.needsAttention)
  }

  @Test func retriesOnlyTheBooksThatFailed() async {
    let queue = makeQueue(FakeDeliveryChannel(.succeed, .fail(.rejected("550 No")), .succeed))
    queue.send([moby, dracula], to: email)
    await queue.waitUntilFinished()

    queue.retryFailed()
    await queue.waitUntilFinished()

    #expect(queue.rows.map(\.id) == [dracula.id])
    #expect(statuses(queue) == [.sent])
  }

  @Test func retryLeavesAnUnconfirmedBookAlone() async {
    let unreachable = SendFailure.connectionFailed(host: "smtp.gmail.com")
    let queue = makeQueue(
      FakeDeliveryChannel(
        .fail(unreachable), .fail(unreachable), .fail(.unconfirmed(host: "smtp.gmail.com")),
        .succeed))
    queue.send([moby, dracula], to: email)
    await queue.waitUntilFinished()

    queue.retryFailed()
    await queue.waitUntilFinished()

    #expect(queue.rows.map(\.id) == [moby.id])
    #expect(statuses(queue) == [.sent])
  }

  @Test func clearsOnlyAFinishedQueue() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let queue = makeQueue(channel)
    queue.send([moby], to: email)
    await channel.waitUntilDeliveryStarts()

    queue.dismiss()
    #expect(!queue.rows.isEmpty)

    queue.cancel()
    await queue.waitUntilFinished()
    queue.dismiss()
    #expect(queue.rows.isEmpty)
    #expect(queue.summary == nil)
  }

  @Test(arguments: [
    (QueueStatus.waiting, "Waiting"), (.preparing, "Preparing"),
    (.uploading(0.5), "Uploading · 50%"),
    (.cancelled, "Cancelled"),
  ])
  func describesEachStatusOfAPDF(status: QueueStatus, detail: String) {
    #expect(QueueRow(book: meditations, status: status).detail == detail)
  }

  @Test func namesEveryFixAmazonNeeds() {
    let row = QueueRow(book: moby, status: .sent, fixes: EPUBFix.allCases)

    #expect(row.fixesNote == "Fixed 4 issues Amazon rejects (encoding, language, links, images)")
    #expect(
      QueueRow(book: moby, status: .sent, fixes: [.removedEmptyImages]).fixesNote
        == "Fixed 1 issue Amazon rejects (images)")
  }
}
