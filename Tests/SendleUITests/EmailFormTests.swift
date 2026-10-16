import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
struct EmailFormTests {
  let settings = InMemorySettingsStore()
  let secrets = MemorySecretStore()
  let channels = FakeDeliveryChannelFactory()

  func makeForm(
    settings: InMemorySettingsStore? = nil,
    channels: FakeDeliveryChannelFactory? = nil
  ) -> EmailForm {
    let settings = settings ?? self.settings
    return EmailForm(
      configure: ConfigureEmail(settings: settings, secrets: secrets),
      sendTest: SendTestEmail(
        settings: settings, channels: channels ?? self.channels, staging: FakeStagingArea()))
  }

  func filled(_ form: EmailForm) -> EmailForm {
    form.kindleAddress = "reader@kindle.com"
    form.senderAddress = "me@gmail.com"
    form.password = "abcd efgh ijkl mnop"
    return form
  }

  @Test func savesAPresetProviderAndForgetsTheTypedPassword() async {
    let form = filled(makeForm())

    #expect(await form.save())

    #expect(await settings.settings.email == .fixture)
    #expect(await secrets.passwords["me@gmail.com"] == "abcdefghijklmnop")
    #expect(form.password.isEmpty)
    #expect(form.hasSavedPassword)
    #expect(form.issues.isEmpty)
  }

  @Test func savesACustomServer() async {
    let form = filled(makeForm())
    form.provider = .custom
    form.customHost = " mail.example.com "
    form.customPort = "465"
    form.customSecurity = .implicitTLS

    #expect(await form.save())

    #expect(
      await settings.settings.email?.server
        == SMTPServer(host: "mail.example.com", port: 465, security: .implicitTLS))
  }

  @Test func aSecondSaveWhileOneRunsIsIgnored() async {
    let form = filled(makeForm())

    let first = Task { await form.save() }
    let second = Task { await form.save() }

    #expect(await first.value)
    #expect(await second.value == false)
    #expect(await settings.settings.email == .fixture)
  }

  @Test func showsEveryProblemAtOnce() async {
    let form = makeForm()
    form.provider = .custom

    #expect(!(await form.save()))

    #expect(
      form.issues == [
        .invalidKindleAddress, .invalidSenderAddress, .missingServer, .missingPassword,
      ]
    )
    #expect(form.issues.allSatisfy { !form.message(for: $0).isEmpty })
  }

  @Test func treatsAPortThatIsNotANumberAsMissing() async {
    let form = filled(makeForm())
    form.provider = .custom
    form.customHost = "mail.example.com"
    form.customPort = "smtp"

    #expect(!(await form.save()))
    #expect(form.issues == [.missingServer])
  }

  @Test func explainsAFailedSave() async {
    let form = filled(makeForm(settings: InMemorySettingsStore(failure: .writeFailed("disk full"))))

    #expect(!(await form.save()))
    #expect(form.saveError == "Couldn't save the settings: disk full")
  }

  @Test func fillsFromSavedSettingsAndKeepsTheSavedPassword() async {
    await secrets.setPassword("saved", for: "me@gmail.com")
    let form = makeForm()

    form.fill(from: .fixture)

    #expect(form.kindleAddress == "reader@kindle.com")
    #expect(form.senderAddress == "me@gmail.com")
    #expect(form.provider == .gmail)
    #expect(form.password.isEmpty)
    #expect(form.hasSavedPassword)
    #expect(await form.save())
    #expect(await secrets.passwords["me@gmail.com"] == "saved")
  }

  @Test func fillsACustomServer() {
    let form = makeForm()
    let server = SMTPServer(host: "mail.example.com", port: 2525, security: .startTLS)

    form.fill(
      from: EmailSettings(
        kindleAddress: .fixture, senderAddress: "me@example.com", provider: .custom,
        server: server))

    #expect(form.customHost == "mail.example.com")
    #expect(form.customPort == "2525")
    #expect(form.customSecurity == .startTLS)
  }

  @Test func fillingWithNothingClearsTheForm() async {
    let form = makeForm()
    form.fill(from: .fixture)
    form.kindleAddress = "typed"
    _ = await form.save()

    form.fill(from: nil)

    #expect(form.kindleAddress.isEmpty)
    #expect(form.senderAddress.isEmpty)
    #expect(form.issues.isEmpty)
    #expect(!form.hasSavedPassword)
  }

  @Test func checksTheKindleAddressAlone() {
    let form = makeForm()
    form.kindleAddress = "reader"
    #expect(!form.checkKindleAddress())
    #expect(form.issues == [.invalidKindleAddress])

    form.kindleAddress = "reader@kindle.com\n"
    #expect(form.checkKindleAddress())
    #expect(form.issues.isEmpty)
  }

  @Test func warnsAboutAKindleAddressThatIsNotAmazons() {
    let form = makeForm()
    form.kindleAddress = "reader@kindle.com"
    #expect(form.kindleAddressWarning == nil)

    form.kindleAddress = "reader@gmail.com"
    #expect(form.kindleAddressWarning != nil)
  }

  @Test func pointsToWhereGmailAndICloudMakeAppPasswords() {
    let form = makeForm()

    #expect(form.appPasswordLink == URL(string: "https://myaccount.google.com/apppasswords"))
    form.provider = .iCloud
    #expect(form.appPasswordLink == URL(string: "https://account.apple.com"))
    form.provider = .fastmail
    #expect(form.appPasswordLink == nil)
    #expect(
      MailProvider.allCases.allSatisfy { provider in
        form.provider = provider
        return !form.appPasswordHelp.isEmpty
      })
  }

  // MARK: Saved password

  @Test func aSavedPasswordBelongsToItsSender() {
    let form = makeForm()
    form.fill(from: .fixture)
    #expect(form.passwordPrompt == "Saved in Keychain. Type to replace it.")

    form.senderAddress = "other@gmail.com"
    #expect(form.passwordPrompt == "App password")

    form.senderAddress = "me@gmail.com\n"
    #expect(form.passwordPrompt == "Saved in Keychain. Type to replace it.")
  }

  @Test func aStorageFailureClearsTheEarlierIssues() async {
    let form = filled(makeForm(settings: InMemorySettingsStore(failure: .writeFailed("disk full"))))
    form.kindleAddress = "nope"
    #expect(!(await form.save()))
    #expect(form.issues == [.invalidKindleAddress])

    form.kindleAddress = "reader@kindle.com"
    #expect(!(await form.save()))

    #expect(form.issues.isEmpty)
    #expect(form.saveError == "Couldn't save the settings: disk full")
  }

  // MARK: Send test

  @Test func savesThenSendsATestDocument() async {
    let form = filled(makeForm())

    await form.sendTest()

    #expect(await settings.settings.email == .fixture)
    #expect(channels.deliveryChannel.deliveries.map(\.name) == ["Sendle test"])
    #expect(channels.deliveryChannel.deliveries.first?.file.format == .txt)
    #expect(
      form.testStatus
        == .sent(
          "Sent through Gmail. It shows up on your Kindle in a few minutes; "
            + "if it doesn't, check Amazon's approved senders."))
  }

  @Test func explainsATestThatFailed() async {
    let refusing = FakeDeliveryChannelFactory(
      channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    let form = filled(makeForm(channels: refusing))

    await form.sendTest()

    #expect(
      form.testStatus == .failed(ProblemPresenter.problem(for: .authenticationFailed(.gmail))))
  }

  @Test func sendsNoTestOfASetupThatCannotBeSaved() async {
    let form = filled(makeForm())
    form.senderAddress = ""

    await form.sendTest()

    #expect(channels.requestedDestinations.isEmpty)
    #expect(form.testStatus == .idle)
    #expect(form.issues == [.invalidSenderAddress])
  }

  @Test func forgetsTheLastTestWhenRefilled() async {
    let form = filled(makeForm())
    await form.sendTest()

    form.fill(from: .fixture)

    #expect(form.testStatus == .idle)
  }
}
