import Foundation
import Observation
import SendleDomain

/// The Kindle and sender fields, shared by the setup steps and the settings sheet.
@Observable @MainActor
package final class EmailForm {
  package var kindleAddress = ""
  package var senderAddress = ""
  package var provider = MailProvider.gmail
  package var customHost = ""
  package var customPort = "587"
  package var customSecurity = SMTPSecurity.startTLS
  /// Empty keeps the password already saved for this sender.
  package var password = ""
  package private(set) var issues: Set<EmailSetupIssue> = []
  package private(set) var warnings: [EmailSetupWarning] = []
  package private(set) var saveError: String?
  package private(set) var isSaving = false
  package private(set) var hasSavedPassword = false

  private let configure: ConfigureEmail

  package init(configure: ConfigureEmail) {
    self.configure = configure
  }

  /// Shows the saved setup, or a blank form. The password stays empty, which keeps the saved one.
  package func fill(from email: EmailSettings?) {
    let custom = email.flatMap { $0.provider == .custom ? $0.server : nil }
    kindleAddress = email?.kindleAddress.rawValue ?? ""
    senderAddress = email?.senderAddress ?? ""
    provider = email?.provider ?? .gmail
    customHost = custom?.host ?? ""
    customPort = custom.map { String($0.port) } ?? "587"
    customSecurity = custom?.security ?? .startTLS
    password = ""
    issues = []
    warnings = []
    saveError = nil
    hasSavedPassword = email != nil
  }

  /// The first setup step after library access checks only this field.
  package func checkKindleAddress() -> Bool {
    let isPlausible = EmailAddress.isPlausible(trimmed(kindleAddress))
    if isPlausible {
      issues.remove(.invalidKindleAddress)
    } else {
      issues.insert(.invalidKindleAddress)
    }
    return isPlausible
  }

  package func save() async -> Bool {
    isSaving = true
    defer { isSaving = false }
    do {
      warnings = try await configure(input)
      issues = []
      saveError = nil
      password = ""
      hasSavedPassword = true
      return true
    } catch {
      switch error {
      case .invalid(let found):
        issues = Set(found)
        saveError = nil
      case .storage(let failure):
        saveError = "Couldn't save the settings: \(Self.detail(of: failure))"
      }
      return false
    }
  }

  package func message(for issue: EmailSetupIssue) -> String {
    switch issue {
    case .invalidKindleAddress: "Enter your Kindle's Send to Kindle address, like name@kindle.com."
    case .invalidSenderAddress: "Enter the email address Sendle sends from."
    case .missingServer: "Enter the mail server and a port from 1 to 65535."
    case .missingPassword: "Enter an app password for this account."
    }
  }

  /// Amazon only accepts mail for @kindle.com addresses, but Sendle doesn't refuse others.
  package var kindleAddressWarning: String? {
    let address = trimmed(kindleAddress)
    guard EmailAddress.isPlausible(address), !KindleEmail(rawValue: address).isAmazonAddress
    else { return nil }
    return "This isn't a @kindle.com address. Check it under Devices in your Amazon account."
  }

  package var passwordPrompt: String {
    hasSavedPassword ? "Saved in Keychain. Type to replace it." : "App password"
  }

  package var appPasswordHelp: String {
    switch provider {
    case .gmail: "Create an app password in your Google account. It needs 2-Step Verification."
    case .iCloud: "Create an app-specific password at account.apple.com, in Sign-In and Security."
    case .fastmail: "Create an app password in Fastmail, in Settings › Privacy & Security."
    case .custom: "Use the password your mail provider gives you for mail apps."
    }
  }

  package var appPasswordLink: URL? {
    switch provider {
    case .gmail: URL(string: "https://myaccount.google.com/apppasswords")
    case .iCloud: URL(string: "https://account.apple.com")
    case .fastmail, .custom: nil
    }
  }

  private var input: EmailSetupInput {
    let server =
      provider == .custom
      ? SMTPServer(
        host: trimmed(customHost), port: Int(trimmed(customPort)) ?? 0, security: customSecurity)
      : nil
    return EmailSetupInput(
      kindleAddress: kindleAddress, senderAddress: senderAddress, provider: provider,
      customServer: server, password: password)
  }

  private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func detail(of failure: StorageError) -> String {
    switch failure {
    case .writeFailed(let detail): detail
    case .keychain(let status): "the Keychain refused it (\(status))"
    }
  }
}
