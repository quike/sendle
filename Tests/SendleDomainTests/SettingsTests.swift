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
    let settings = AppSettings(
      email: .fixture, layout: .shelf, activeDestination: .usb, sort: .author,
      jumpBar: .compact, showsFormat: false, showsLogs: true,
      kindleAddresses: [.fixture, KindleEmail(rawValue: "pw5@kindle.com")],
      bokoPath: "/Users/reader/bin/boko")
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }

  @Test func readsAFileWrittenBeforeTheseSettings() throws {
    let json = #"""
      {"activeDestination": "usb", "layout": "list", "email": {"kindleAddress": "reader@kindle.com",
      "senderAddress": "me@gmail.com", "provider": "gmail",
      "server": {"host": "smtp.gmail.com", "port": 465, "security": "implicitTLS"}}}
      """#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(settings.email == .fixture)
    #expect(settings.layout == .list)
    #expect(settings.sort == .recent)
    #expect(settings.jumpBar == .full)
    #expect(settings.showsFormat)
    #expect(!settings.showsLogs)
    #expect(settings.bokoPath == nil)
    #expect(settings.savedKindleAddresses == [.fixture])
  }

  /// An older build ignores the keys it doesn't know, so going back to it keeps the setup.
  @Test func anOlderBuildCanStillReadTheFile() throws {
    struct OlderSettings: Decodable {
      let email: EmailSettings?
      let layout: LibraryLayout
      let activeDestination: DestinationKind
    }
    let settings = AppSettings(
      email: .fixture, layout: .list, activeDestination: .usb, sort: .title, showsLogs: true,
      kindleAddresses: [KindleEmail(rawValue: "pw5@kindle.com")], bokoPath: "/opt/boko")
    let old = try JSONDecoder().decode(OlderSettings.self, from: JSONEncoder().encode(settings))
    #expect(old.email == .fixture)
    #expect(old.layout == .list)
    #expect(old.activeDestination == .usb)
  }

  @Test func theActiveAddressIsAlwaysAmongTheSavedOnes() {
    let other = KindleEmail(rawValue: "pw5@kindle.com")
    #expect(AppSettings().savedKindleAddresses == [])
    #expect(AppSettings(email: .fixture).savedKindleAddresses == [.fixture])
    #expect(
      AppSettings(email: .fixture, kindleAddresses: [other]).savedKindleAddresses
        == [.fixture, other])
    #expect(
      AppSettings(
        email: .fixture, kindleAddresses: [other, KindleEmail(rawValue: "READER@kindle.com")]
      )
      .savedKindleAddresses == [other, KindleEmail(rawValue: "READER@kindle.com")])
  }

  @Test func showsFormatDefaultsToOn() throws {
    #expect(AppSettings().showsFormat)
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.showsFormat)
  }

  @Test func missingKeysFallBackToDefaults() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings == .defaults)
  }

  @Test func unknownValuesFromNewerVersionsFallBackToDefaults() throws {
    let json = #"""
      {"layout": "carousel", "activeDestination": "bluetooth", "sort": "rating",
      "jumpBar": "huge", "showsFormat": "yes", "showsLogs": "yes", "kindleAddresses": 7, "bokoPath": false}
      """#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(settings == .defaults)
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
    #expect(LibrarySort.allCases.map(\.rawValue) == ["recent", "title", "author"])
    #expect(JumpBarStyle.allCases.map(\.rawValue) == ["full", "compact"])
  }
}
