import Foundation
import SMTPKit
import SendleDomain
import SendleMail
import SendleTestSupport
import Testing

struct EmailChannelFactoryTests {
  func factory(
    _ saved: AppSettings = AppSettings(email: .fixture),
    secrets: MemorySecretStore = MemorySecretStore(["me@gmail.com": "app-password"])
  ) -> EmailChannelFactory {
    EmailChannelFactory(
      settings: InMemorySettingsStore(saved), secrets: secrets,
      makeTransport: { _ in ScriptedSMTPTransport([]) })
  }

  func failure(of factory: EmailChannelFactory) async -> SendFailure? {
    do {
      _ = try await factory.channel(to: .fixture)
      return nil
    } catch {
      return error
    }
  }

  @Test func needsTheEmailSetUp() async {
    #expect(await failure(of: factory(.defaults)) == .notConfigured)
  }

  @Test func needsTheSendersPassword() async {
    #expect(await failure(of: factory(secrets: MemorySecretStore())) == .passwordUnavailable)
  }

  @Test func saysSoWhenTheKeychainRefuses() async {
    let refusing = MemorySecretStore(readFailure: .keychain(status: -25293))

    #expect(await failure(of: factory(secrets: refusing)) == .passwordUnavailable)
  }

  @Test func sendsToTheChosenKindle() async throws {
    let other = KindleEmail(rawValue: "other@kindle.com")

    let channel = try await factory().channel(to: other)

    #expect(channel.recipient == other)
  }
}
