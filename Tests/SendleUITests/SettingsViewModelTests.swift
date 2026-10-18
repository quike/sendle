import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
final class FakeLoginItem: LoginItem {
  struct Refusal: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
  }

  var status = LoginItemStatus.disabled
  var statusAfterEnabling = LoginItemStatus.enabled
  var refuses = false

  func setEnabled(_ enabled: Bool) throws {
    if refuses { throw Refusal() }
    status = enabled ? statusAfterEnabling : .disabled
  }
}

@MainActor
struct SettingsViewModelTests {
  let settings = InMemorySettingsStore(AppSettings(email: .fixture))
  let secrets = MemorySecretStore(["me@gmail.com": "saved"])
  let loginItem = FakeLoginItem()
  let converter = FakeFormatConverter(isAvailable: false)
  let log = FakeActivityLog()

  func makeModel(
    _ settings: InMemorySettingsStore? = nil,
    toolRuns: Bool = true
  ) -> SettingsViewModel {
    let settings = settings ?? self.settings
    return SettingsViewModel(
      configure: ConfigureEmail(settings: settings, secrets: secrets),
      sendTest: SendTestEmail(
        settings: settings, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      addresses: ManageKindleAddresses(settings: settings),
      chooseTool: ChooseConverterTool(
        settings: settings, choice: converter, isExecutable: { _ in toolRuns }),
      settings: settings, loginItem: loginItem, converter: converter, log: log)
  }

  /// A model with nothing saved yet, as before the first setup.
  func makeUnconfiguredModel() -> SettingsViewModel {
    let empty = InMemorySettingsStore()
    return SettingsViewModel(
      configure: ConfigureEmail(settings: empty, secrets: MemorySecretStore()),
      sendTest: SendTestEmail(
        settings: empty, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      addresses: ManageKindleAddresses(settings: empty),
      chooseTool: ChooseConverterTool(settings: empty, choice: converter),
      settings: empty, loginItem: loginItem, converter: converter)
  }

  // MARK: Front page and search

  @Test func opensOnTheFrontPageWithASummaryOfEachSection() async {
    let model = makeModel()

    await model.open(at: nil)

    #expect(model.section == nil)
    #expect(
      SettingsSection.allCases.map { model.summary(of: $0) } == [
        "Doesn't open at login · A–Z bar: Full · Logs off", "reader@kindle.com",
        "Gmail · me@gmail.com", "boko not found",
      ])
  }

  @Test func summarisesASetupThatIsNotThereYet() async {
    let model = makeUnconfiguredModel()

    await model.open(at: nil)

    #expect(!model.hasEmailSetup)
    #expect(model.summary(of: .kindle) == "Not set up")
    #expect(model.summary(of: .sender) == "Not set up")
  }

  @Test func sumsUpTheSavedSenderUntilTheEditsAreSaved() async {
    let model = makeModel()
    await model.open(at: .sender)
    model.form.provider = .fastmail
    model.form.senderAddress = "me@fastmail.com"
    model.form.password = "abcdefghijklmnop"

    model.show(nil)
    #expect(model.summary(of: .sender) == "Gmail · me@gmail.com")

    #expect(await model.save())
    #expect(model.summary(of: .sender) == "Fastmail · me@fastmail.com")
  }

  @Test func goesToASectionAndBack() async {
    let model = makeModel()
    await model.open(at: nil)

    model.show(.usb)
    #expect(model.section == .usb)

    model.show(nil)
    #expect(model.section == nil)
  }

  @Test func aSearchResultOpensItsSectionAndMarksTheSetting() async {
    let model = makeModel()
    await model.open(at: nil)
    model.query = "pass"
    #expect(model.results == [.appPassword])

    model.choose(.appPassword)

    #expect(model.section == .sender)
    #expect(model.highlighted == .appPassword)
    #expect(model.query.isEmpty)
  }

  // MARK: General

  @Test func readsTheJumpBarAndLogsBeforeSettingsOpen() async {
    let model = makeModel(InMemorySettingsStore(AppSettings(jumpBar: .compact, showsLogs: true)))

    await model.start()

    #expect(model.jumpBar == .compact)
    #expect(model.showsLogs)
  }

  @Test func savesTheJumpBarAndLogsAtOnceAndSaysSo() async {
    let model = makeModel()
    var changes = 0
    model.onChange = { changes += 1 }
    await model.open(at: .general)

    await model.setJumpBar(.compact)
    await model.setShowsLogs(true)

    #expect(await settings.settings.jumpBar == .compact)
    #expect(await settings.settings.showsLogs)
    #expect(changes == 2)
    #expect(model.summary(of: .general) == "Doesn't open at login · A–Z bar: Compact · Logs on")
  }

  // MARK: Kindle addresses

  @Test func listsTheSavedAddressesWithTheActiveOne() async {
    let pw5 = KindleEmail(rawValue: "pw5@kindle.com")
    let model = makeModel(
      InMemorySettingsStore(AppSettings(email: .fixture, kindleAddresses: [.fixture, pw5])))

    await model.open(at: .kindle)

    #expect(model.kindleAddresses == [.fixture, pw5])
    #expect(model.activeKindleAddress == .fixture)
    #expect(model.summary(of: .kindle) == "reader@kindle.com · 2 saved")
  }

  @Test func marksTheActiveAddressInItsSavedSpelling() async {
    let pw5 = KindleEmail(rawValue: "pw5@kindle.com")
    let model = makeModel(
      InMemorySettingsStore(
        AppSettings(
          email: .fixture.with(kindleAddress: KindleEmail(rawValue: "PW5@Kindle.com")),
          kindleAddresses: [.fixture, pw5])))

    await model.open(at: .kindle)

    #expect(model.kindleAddresses == [.fixture, pw5])
    #expect(model.activeKindleAddress == pw5)
  }

  @Test func addsAnAddressAndMakesItActive() async {
    let model = makeModel()
    var changes = 0
    model.onChange = { changes += 1 }
    await model.open(at: .kindle)
    model.newKindleAddress = "pw5@kindle.com"

    #expect(await model.addKindleAddress())

    #expect(model.activeKindleAddress == KindleEmail(rawValue: "pw5@kindle.com"))
    #expect(model.kindleAddresses.count == 2)
    #expect(model.newKindleAddress.isEmpty)
    #expect(model.form.kindleAddress == "pw5@kindle.com")
    #expect(changes == 1)
  }

  @Test func explainsAnAddressItCannotAdd() async {
    let model = makeModel()
    await model.open(at: .kindle)
    model.newKindleAddress = "reader"

    #expect(await !model.addKindleAddress())

    #expect(
      model.kindleAddressError
        == "Enter your Kindle's Send to Kindle address, like name@kindle.com.")
  }

  @Test func warnsAboutAnAddressAmazonWontDeliverTo() async {
    let model = makeModel()
    await model.open(at: .kindle)
    model.newKindleAddress = "reader@gmail.com"

    await model.addKindleAddress()

    #expect(model.kindleAddressWarning?.contains("@kindle.com") == true)
  }

  @Test func switchesTheActiveAddressAndKeepsTheActiveOneFromBeingRemoved() async {
    let model = makeModel()
    await model.open(at: .kindle)
    model.newKindleAddress = "pw5@kindle.com"
    await model.addKindleAddress()

    await model.activate(.fixture)
    #expect(model.activeKindleAddress == .fixture)

    await model.remove(.fixture)
    #expect(model.kindleAddressError == "Make another address active before removing this one.")
    await model.remove(KindleEmail(rawValue: "pw5@kindle.com"))
    #expect(model.kindleAddresses == [.fixture])
  }

  @Test func opensAtASectionWithTheSavedSetup() async {
    let model = makeModel()

    await model.open(at: .sender)

    #expect(model.section == .sender)
    #expect(model.form.senderAddress == "me@gmail.com")
  }

  @Test func reopeningDiscardsUnsavedEdits() async {
    let model = makeModel()
    await model.open(at: .kindle)
    model.form.kindleAddress = "typo@kindle.com"

    await model.open(at: .kindle)

    #expect(model.form.kindleAddress == "reader@kindle.com")
  }

  @Test func savesTheEmailSetup() async {
    let model = makeModel()
    await model.open(at: .kindle)
    model.form.kindleAddress = "other@kindle.com"

    #expect(await model.save())
    #expect(
      await settings.settings.email?.kindleAddress == KindleEmail(rawValue: "other@kindle.com"))
  }

  @Test func aSaveMissingSenderDetailsShowsTheSenderSection() async {
    let model = makeUnconfiguredModel()
    await model.open(at: .kindle)
    model.form.kindleAddress = "reader@kindle.com"

    #expect(await !model.save())
    #expect(model.section == .sender)
  }

  @Test func aSaveMissingTheKindleAddressShowsTheKindleSection() async {
    let model = makeUnconfiguredModel()
    await model.open(at: .sender)
    model.form.senderAddress = "me@gmail.com"
    model.form.password = "abcdefghijklmnop"

    #expect(await !model.save())
    #expect(model.section == .kindle)
  }

  @Test func aSaveWithProblemsHereStaysHere() async {
    let model = makeUnconfiguredModel()
    await model.open(at: .sender)

    #expect(await !model.save())
    #expect(model.section == .sender)
  }

  @Test func turnsLaunchAtLoginOnAndOff() async {
    let model = makeModel()
    await model.open(at: .general)

    model.setLaunchAtLogin(true)
    #expect(model.launchAtLogin == .enabled)

    model.setLaunchAtLogin(false)
    #expect(model.launchAtLogin == .disabled)
    #expect(model.launchAtLoginNote == nil)
  }

  @Test func saysWhenMacOSWantsTheLoginItemApproved() async {
    loginItem.statusAfterEnabling = .requiresApproval
    let model = makeModel()
    await model.open(at: .general)

    model.setLaunchAtLogin(true)

    #expect(model.launchAtLogin == .requiresApproval)
    #expect(model.launchAtLoginNote?.contains("Login Items") == true)
  }

  @Test func explainsWhyLaunchAtLoginCouldNotChange() async {
    loginItem.refuses = true
    let model = makeModel()
    await model.open(at: .general)

    model.setLaunchAtLogin(true)

    #expect(model.launchAtLogin == .disabled)
    #expect(model.launchAtLoginError == "Couldn't change this: Operation not permitted")
    #expect(log.summary.first?.hasPrefix("error APP Couldn't turn launch at login on: ") == true)
  }

  @Test func readsTheLoginItemEachTimeItOpens() async {
    let model = makeModel()
    loginItem.status = .unavailable

    await model.open(at: .general)

    #expect(model.launchAtLogin == .unavailable)
    #expect(model.launchAtLoginNote != nil)
  }

  // MARK: USB

  @Test func explainsWhatBokoIsForUntilItIsInstalled() async {
    let model = makeModel()

    await model.open(at: .usb)

    #expect(model.boko == nil)
    #expect(model.bokoTitle == "boko not found")
    #expect(
      model.bokoNote
        == "Your Kindle can't read EPUB, so Sendle converts EPUBs with boko before copying "
        + "them. Until it's installed, PDFs go over USB and EPUBs go by email.")
  }

  @Test func showsWhereBokoIsOnceInstalled() async {
    let model = makeModel()
    await model.open(at: .usb)

    converter.install()
    await model.open(at: .usb)

    #expect(model.boko == converter.toolURL)
    #expect(model.bokoTitle == "boko found")
    #expect(
      model.bokoNote == "EPUBs are converted to AZW3 before they're copied to your Kindle.")
  }

  @Test func usesTheBokoTheUserChoosesAndResets() async {
    let chosen = URL(filePath: "/Users/reader/bin/boko")
    let model = makeModel()
    var changes = 0
    model.onChange = { changes += 1 }
    await model.open(at: .usb)

    await model.chooseBoko(chosen)
    #expect(model.boko == chosen)
    #expect(model.chosenBoko == chosen)
    #expect(await settings.settings.bokoPath == chosen.path)

    await model.resetBoko()
    #expect(model.chosenBoko == nil)
    #expect(await settings.settings.bokoPath == nil)
    #expect(changes == 2)
  }

  @Test func refusesAFileThatCannotRun() async {
    let model = makeModel(toolRuns: false)
    await model.open(at: .usb)

    await model.chooseBoko(URL(filePath: "/Users/reader/Downloads/boko.zip"))

    #expect(model.bokoError == "boko.zip isn't a program Sendle can run.")
    #expect(model.chosenBoko == nil)
  }

  @Test func saysWhenTheChosenBokoIsGone() async {
    let model = makeModel()
    await model.open(at: .usb)
    await model.chooseBoko(URL(filePath: "/Users/reader/bin/boko"))

    converter.removeChosenTool()
    await model.open(at: .usb)

    #expect(model.bokoTitle == "boko not found")
    #expect(
      model.bokoNote
        == "Sendle looks only where you chose: /Users/reader/bin/boko. Choose it again, or reset "
        + "to look in the usual folders.")
  }
}
