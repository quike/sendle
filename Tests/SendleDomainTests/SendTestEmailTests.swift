import Foundation
import SendleDomain
import SendleTestSupport
import Testing

struct SendTestEmailTests {
  @Test func sendsASmallTextDocumentToTheKindleAddress() async throws {
    let channels = FakeDeliveryChannelFactory()
    let staging = FakeStagingArea()
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(AppSettings(email: .fixture)), channels: channels,
      staging: staging)

    try await sendTest()

    let delivery = try #require(channels.deliveryChannel.deliveries.first)
    #expect(delivery.name == "Sendle test")
    #expect(delivery.file.format == .txt)
    #expect(channels.requestedDestinations == [.email(.fixture)])
    let contents = try #require(staging.snapshot.files[delivery.file.url])
    #expect(String(decoding: contents, as: UTF8.self).contains("Sendle can reach your Kindle"))
    #expect(staging.snapshot.removed == staging.snapshot.made)
  }

  @Test func logsTheTestUnderItsOwnHeading() async throws {
    let log = FakeActivityLog()
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(AppSettings(email: .fixture)),
      channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea(), log: log)

    try await sendTest()

    #expect(log.summary == ["info MAIL Send test · reader@kindle.com", "info MAIL Send test sent"])
    #expect(log.entries().first?.heading == .sendTest)
  }

  @Test func logsAFailedTest() async {
    let log = FakeActivityLog()
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(AppSettings(email: .fixture)),
      channels: FakeDeliveryChannelFactory(
        channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail)))),
      staging: FakeStagingArea(), log: log)

    await #expect(throws: SendFailure.self) { try await sendTest() }

    #expect(
      log.summary.last == "error MAIL Send test failed: the mail server didn't accept the password")
  }

  @Test func logsACancelledTestAsInfo() async {
    let log = FakeActivityLog()
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(AppSettings(email: .fixture)),
      channels: FakeDeliveryChannelFactory(channel: FakeDeliveryChannel(.fail(.cancelled))),
      staging: FakeStagingArea(), log: log)

    await #expect(throws: SendFailure.cancelled) { try await sendTest() }

    #expect(log.summary.last == "info MAIL Send test cancelled")
  }

  @Test func needsTheEmailSetupFirst() async {
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(), channels: FakeDeliveryChannelFactory(),
      staging: FakeStagingArea())

    await #expect(throws: SendFailure.notConfigured) { try await sendTest() }
  }

  @Test func reportsARejectedPassword() async {
    let channel = FakeDeliveryChannel(.fail(.authenticationFailed(.gmail)))
    let staging = FakeStagingArea()
    let sendTest = SendTestEmail(
      settings: InMemorySettingsStore(AppSettings(email: .fixture)),
      channels: FakeDeliveryChannelFactory(channel: channel), staging: staging)

    await #expect(throws: SendFailure.authenticationFailed(.gmail)) { try await sendTest() }
    #expect(staging.snapshot.removed == staging.snapshot.made)
  }
}
