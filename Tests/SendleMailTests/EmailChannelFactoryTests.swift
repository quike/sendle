import Foundation
import SMTPKit
import SendleDomain
import SendleMail
import SendleTestSupport
import Testing

struct EmailChannelFactoryTests {
  let log = FakeActivityLog()

  func factory(
    _ saved: AppSettings = AppSettings(email: .fixture),
    secrets: MemorySecretStore = MemorySecretStore(["me@gmail.com": "app-password"])
  ) -> EmailChannelFactory {
    EmailChannelFactory(
      settings: InMemorySettingsStore(saved), secrets: secrets, log: log,
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
    #expect(log.summary == ["error MAIL No app password is saved for me@gmail.com"])
  }

  @Test func saysSoWhenTheKeychainRefuses() async {
    let refusing = MemorySecretStore(readFailure: .keychain(status: -25293))

    #expect(await failure(of: factory(secrets: refusing)) == .passwordUnavailable)
    #expect(
      log.summary == [
        "error MAIL Couldn't read the app password for me@gmail.com: "
          + "the Keychain refused it (-25293)"
      ])
  }

  @Test func sendsToTheChosenKindle() async throws {
    let other = KindleEmail(rawValue: "other@kindle.com")

    let channel = try await factory().channel(to: other)

    #expect(channel.recipient == other)
  }
}
