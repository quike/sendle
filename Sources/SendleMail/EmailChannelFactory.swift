import SMTPKit
import SendleDomain

/// Builds the channel for a send from the saved sender and its Keychain password.
public struct EmailChannelFactory: Sendable {
  private let settings: any SettingsStore
  private let secrets: any SecretStore
  private let makeTransport: EmailDeliveryChannel.MakeTransport

  public init(
    settings: any SettingsStore,
    secrets: any SecretStore,
    makeTransport: @escaping EmailDeliveryChannel.MakeTransport = EmailDeliveryChannel.streamTask
  ) {
    self.settings = settings
    self.secrets = secrets
    self.makeTransport = makeTransport
  }

  public func channel(to kindle: KindleEmail) async throws(SendFailure) -> EmailDeliveryChannel {
    guard let email = await settings.load().email else { throw .notConfigured }
    let password: String?
    do {
      password = try await secrets.password(for: email.senderAddress)
    } catch {
      throw .passwordUnavailable
    }
    guard let password, !password.isEmpty else { throw .passwordUnavailable }
    return EmailDeliveryChannel(
      email: email, recipient: kindle, password: password, makeTransport: makeTransport)
  }
}
