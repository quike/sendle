import SendleDomain
import SendleTestSupport
import Testing

struct ConfigureEmailTests {
  let settings = InMemorySettingsStore()
  let secrets = MemorySecretStore()
  let log = FakeActivityLog()
  var configure: ConfigureEmail { ConfigureEmail(settings: settings, secrets: secrets, log: log) }

  func input(
    kindle: String = "reader@kindle.com",
    sender: String = "me@gmail.com",
    provider: MailProvider = .gmail,
    server: SMTPServer? = nil,
    password: String = "abcdefghijklmnop"
  ) -> EmailSetupInput {
    EmailSetupInput(
      kindleAddress: kindle, senderAddress: sender, provider: provider, customServer: server,
      password: password)
  }

  @Test func savesThePresetServerAndKeepsThePasswordInTheSecretStore() async throws {
    let warnings = try await configure(
      input(sender: "me@icloud.com", provider: .iCloud, password: "abcd-efgh-ijkl-mnop"))

    #expect(warnings.isEmpty)
    #expect(
      await settings.settings.email
        == EmailSettings(
          kindleAddress: .fixture, senderAddress: "me@icloud.com", provider: .iCloud,
          server: SMTPServer(host: "smtp.mail.me.com", port: 587, security: .startTLS)))
    #expect(await secrets.passwords == ["me@icloud.com": "abcd-efgh-ijkl-mnop"])
  }

  @Test func keepsTheKindleAddressAmongTheSavedOnesInItsSavedSpelling() async throws {
    let paperwhite = KindleEmail(rawValue: "pw5@kindle.com")
    try await settings.update { $0.email = .fixture }

    _ = try await configure(input(kindle: "pw5@kindle.com"))
    _ = try await configure(input(kindle: "PW5@kindle.com"))

    #expect(await settings.settings.savedKindleAddresses == [.fixture, paperwhite])
    #expect(await settings.settings.email?.kindleAddress == paperwhite)
    #expect(
      log.summary.last
        == "info APP Saved the email setup: me@gmail.com through smtp.gmail.com:465 to pw5@kindle.com"
    )
  }

  @Test func logsTheSavedSetupButNotThePassword() async throws {
    _ = try await configure(input(password: "abcdefghijklmnop"))

    #expect(
      log.summary == [
        "info APP Saved the email setup: me@gmail.com through smtp.gmail.com:465 to reader@kindle.com"
      ])
  }

  @Test func acceptsAGmailAppPasswordPastedWithItsSpaces() async throws {
    _ = try await configure(input(kindle: " reader@kindle.com ", password: "abcd efgh ijkl mnop\n"))

    #expect(await settings.settings.email?.kindleAddress == .fixture)
    #expect(await secrets.passwords["me@gmail.com"] == "abcdefghijklmnop")
  }

  @Test func keepsInnerSpacesForOtherProviders() async throws {
    let server = SMTPServer(host: "mail.example.com", port: 587, security: .startTLS)
    _ = try await configure(
      input(sender: "me@example.com", provider: .custom, server: server, password: " pass word \n"))

    #expect(await secrets.passwords["me@example.com"] == "pass word")
  }

  @Test func reportsEveryProblemAtOnce() async {
    await #expect(
      throws: EmailSetupError.invalid([
        .invalidKindleAddress, .invalidSenderAddress, .missingServer, .missingPassword,
      ])
    ) {
      try await configure(input(kindle: "reader", sender: "me@", provider: .custom, password: ""))
    }
    #expect(await settings.settings.email == nil)
  }

  @Test func aCustomServerNeedsAHostAndAValidPort() async {
    let server = SMTPServer(host: "mail.example.com", port: 0, security: .startTLS)
    await #expect(throws: EmailSetupError.invalid([.missingServer])) {
      try await configure(input(provider: .custom, server: server))
    }
  }

  @Test func aBlankPasswordKeepsTheOneAlreadySaved() async throws {
    await secrets.setPassword("saved", for: "me@gmail.com")

    _ = try await configure(input(password: ""))

    #expect(await secrets.passwords["me@gmail.com"] == "saved")
  }

  @Test func changingTheSenderRemovesTheOldPassword() async throws {
    _ = try await configure(input(sender: "old@gmail.com"))
    _ = try await configure(input(sender: "new@gmail.com"))

    #expect(await secrets.passwords == ["new@gmail.com": "abcdefghijklmnop"])
  }

  @Test func warnsWhenTheKindleAddressIsNotAnAmazonOne() async throws {
    let warnings = try await configure(input(kindle: "reader@gmail.com"))

    #expect(warnings == [.kindleAddressNotAmazon])
  }

  @Test func reportsAStorageFailure() async {
    let configure = ConfigureEmail(
      settings: InMemorySettingsStore(failure: .writeFailed("disk full")), secrets: secrets,
      log: log)

    await #expect(throws: EmailSetupError.storage(.writeFailed("disk full"))) {
      try await configure(input())
    }
    #expect(log.summary == ["error APP Couldn't save the email setup: disk full"])
  }

  @Test func aFailedSaveKeepsThePreviousSendersPassword() async {
    let secrets = MemorySecretStore(["me@gmail.com": "old"])
    let configure = ConfigureEmail(
      settings: InMemorySettingsStore(
        AppSettings(email: .fixture), failure: .writeFailed("disk full")),
      secrets: secrets)

    await #expect(throws: EmailSetupError.storage(.writeFailed("disk full"))) {
      try await configure(input(sender: "new@gmail.com"))
    }
    #expect(await secrets.passwords["me@gmail.com"] == "old")
  }

  @Test func acceptsAddressesPastedWithATrailingNewline() async throws {
    _ = try await configure(input(kindle: "reader@kindle.com\n", sender: "me@gmail.com\r\n"))

    #expect(await settings.settings.email?.kindleAddress == .fixture)
    #expect(await settings.settings.email?.senderAddress == "me@gmail.com")
  }

  @Test func savesEvenWhenTheOldPasswordCannotBeRemoved() async throws {
    let secrets = MemorySecretStore(
      ["me@gmail.com": "old"], removalFailure: .keychain(status: -25_300))
    let settings = InMemorySettingsStore(AppSettings(email: .fixture))
    let configure = ConfigureEmail(settings: settings, secrets: secrets)

    _ = try await configure(input(sender: "new@gmail.com"))

    #expect(await settings.settings.email?.senderAddress == "new@gmail.com")
    #expect(await secrets.passwords["new@gmail.com"] == "abcdefghijklmnop")
  }

  @Test func describingTheInputNeverShowsThePassword() {
    let typed = input(password: "hunter2-app-pass")
    var dumped = ""
    dump(typed, to: &dumped)

    for text in [String(describing: typed), String(reflecting: typed), "\(typed)", dumped] {
      #expect(!text.contains("hunter2"))
      #expect(text.contains("<redacted>"))
      #expect(text.contains("reader@kindle.com"))
    }
    #expect(String(describing: input(password: "")).contains("<empty>"))
  }
}
