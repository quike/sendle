import SendleDomain
import SendleTestSupport
import Testing

struct ConfigureEmailTests {
  let settings = InMemorySettingsStore()
  let secrets = MemorySecretStore()
  var configure: ConfigureEmail { ConfigureEmail(settings: settings, secrets: secrets) }

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
      settings: InMemorySettingsStore(failure: .writeFailed("disk full")), secrets: secrets)

    await #expect(throws: EmailSetupError.storage(.writeFailed("disk full"))) {
      try await configure(input())
    }
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
}
