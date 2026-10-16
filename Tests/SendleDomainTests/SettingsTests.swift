import Foundation
import SendleDomain
import SendleTestSupport
import Testing

struct MailProviderTests {
  @Test func presetsMatchProviderDocumentation() {
    #expect(
      MailProvider.gmail.defaultServer
        == SMTPServer(host: "smtp.gmail.com", port: 465, security: .implicitTLS))
    #expect(
      MailProvider.iCloud.defaultServer
        == SMTPServer(host: "smtp.mail.me.com", port: 587, security: .startTLS))
    #expect(
      MailProvider.fastmail.defaultServer
        == SMTPServer(host: "smtp.fastmail.com", port: 465, security: .implicitTLS))
    #expect(MailProvider.custom.defaultServer == nil)
  }

  @Test(arguments: [("", 587), ("smtp.example.com", 0), ("smtp.example.com", 70_000)])
  func invalidCustomServers(host: String, port: Int) {
    #expect(!SMTPServer(host: host, port: port, security: .startTLS).isValid)
  }
}

struct SendFailureTests {
  @Test func onlyConnectionFailuresAreRetried() {
    #expect(SendFailure.connectionFailed(host: "smtp.gmail.com").isRetryable)
    #expect(!SendFailure.authenticationFailed(.gmail).isRetryable)
    #expect(!SendFailure.rejected("550").isRetryable)
    #expect(!SendFailure.cancelled.isRetryable)
    #expect(!SendFailure.unconfirmed(host: "smtp.gmail.com").isRetryable)
    #expect(!SendFailure.passwordUnavailable.isRetryable)
  }
}

struct AppSettingsTests {
  @Test func roundTripsThroughJSON() throws {
    let settings = AppSettings(email: .fixture, layout: .shelf, activeDestination: .usb)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }

  @Test func missingKeysFallBackToDefaults() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings == .defaults)
  }

  @Test func unknownValuesFromNewerVersionsFallBackToDefaults() throws {
    let json = #"{"layout": "carousel", "activeDestination": "bluetooth"}"#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(settings.layout == .grid)
    #expect(settings.activeDestination == .email)
  }

  @Test func anEmailBlockThisVersionCannotReadFailsInsteadOfBeingDropped() {
    let json = #"{"email": {"provider": "outlook"}}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
  }
}

struct PersistedEnumTests {
  /// settings.json and history.json store these raw values: renaming one loses saved data.
  @Test func rawValuesNeverChange() {
    #expect(MailProvider.allCases.map(\.rawValue) == ["gmail", "iCloud", "fastmail", "custom"])
    #expect(SMTPSecurity.allCases.map(\.rawValue) == ["implicitTLS", "startTLS"])
    #expect(LibraryLayout.allCases.map(\.rawValue) == ["grid", "list", "shelf"])
    #expect(DestinationKind.allCases.map(\.rawValue) == ["email", "usb"])
    #expect(SendOutcome.allCases.map(\.rawValue) == ["sent", "failed", "unconfirmed"])
  }
}
