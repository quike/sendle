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
