import Foundation

public struct EmailSetupInput: Hashable, Sendable {
  public var kindleAddress: String
  public var senderAddress: String
  public var provider: MailProvider
  public var customServer: SMTPServer?
  /// Empty keeps the password already saved for this sender.
  public var password: String

  public init(
    kindleAddress: String,
    senderAddress: String,
    provider: MailProvider,
    customServer: SMTPServer? = nil,
    password: String
  ) {
    self.kindleAddress = kindleAddress
    self.senderAddress = senderAddress
    self.provider = provider
    self.customServer = customServer
    self.password = password
  }
}

extension EmailSetupInput: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// Every textual form hides the password, so logs and test failures can't leak it.
  public var description: String {
    let server = customServer.map { String(describing: $0) } ?? "nil"
    return "EmailSetupInput(kindleAddress: \(kindleAddress), senderAddress: \(senderAddress), "
      + "provider: \(provider), customServer: \(server), password: \(redactedPassword))"
  }

  public var debugDescription: String { description }

  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "kindleAddress": kindleAddress, "senderAddress": senderAddress, "provider": provider,
        "customServer": customServer as Any, "password": redactedPassword,
      ])
  }

  private var redactedPassword: String { password.isEmpty ? "<empty>" : "<redacted>" }
}

public enum EmailSetupIssue: Hashable, Sendable {
  case invalidKindleAddress
  case invalidSenderAddress
  case missingServer
  case missingPassword
}

public enum EmailSetupWarning: Hashable, Sendable {
  case kindleAddressNotAmazon
}

public enum EmailSetupError: Error, Hashable, Sendable {
  case invalid([EmailSetupIssue])
  case storage(StorageError)
}

public struct ConfigureEmail: Sendable {
  private let settings: any SettingsStore
  private let secrets: any SecretStore

  public init(settings: any SettingsStore, secrets: any SecretStore) {
    self.settings = settings
    self.secrets = secrets
  }

  /// Validates every field at once, then saves the password and settings.
  public func callAsFunction(
    _ input: EmailSetupInput
  ) async throws(EmailSetupError) -> [EmailSetupWarning] {
    let kindle = KindleEmail(
      rawValue: input.kindleAddress.trimmingCharacters(in: .whitespacesAndNewlines))
    let sender = input.senderAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = Self.normalized(input.password, for: input.provider)
    let server = input.provider.defaultServer ?? input.customServer

    var issues: [EmailSetupIssue] = []
    if !EmailAddress.isPlausible(kindle.rawValue) { issues.append(.invalidKindleAddress) }
    if !EmailAddress.isPlausible(sender) { issues.append(.invalidSenderAddress) }
    if server?.isValid != true { issues.append(.missingServer) }
    if password.isEmpty, (try? await secrets.password(for: sender)) == nil {
      issues.append(.missingPassword)
    }
    guard issues.isEmpty, let server else { throw .invalid(issues) }

    let email = EmailSettings(
      kindleAddress: kindle, senderAddress: sender, provider: input.provider, server: server)
    let previous: AppSettings
    do throws(StorageError) {
      if !password.isEmpty {
        try await secrets.setPassword(password, for: sender)
      }
      previous = try await settings.update { $0.email = email }
    } catch {
      throw .storage(error)
    }
    // The setup is saved: a password left behind for the old sender is untidy, not a failure.
    if let oldSender = previous.email?.senderAddress, oldSender != sender {
      try? await secrets.removePassword(for: oldSender)
    }
    return kindle.isAmazonAddress ? [] : [.kindleAddressNotAmazon]
  }

  /// Pasted passwords often carry a trailing newline, and Google shows app passwords in
  /// groups of four separated by spaces that are not part of the password.
  static func normalized(_ password: String, for provider: MailProvider) -> String {
    let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
    return provider == .gmail ? trimmed.filter { !$0.isWhitespace } : trimmed
  }
}
