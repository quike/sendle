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
    let kindle = KindleEmail(rawValue: input.kindleAddress.trimmingCharacters(in: .whitespaces))
    let sender = input.senderAddress.trimmingCharacters(in: .whitespaces)
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

    do throws(StorageError) {
      var current = await settings.load()
      let previous = current.email?.senderAddress
      if !password.isEmpty {
        try await secrets.setPassword(password, for: sender)
      }
      current.email = EmailSettings(
        kindleAddress: kindle, senderAddress: sender, provider: input.provider, server: server)
      try await settings.save(current)
      if let previous, previous != sender {
        try await secrets.removePassword(for: previous)
      }
    } catch {
      throw .storage(error)
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
