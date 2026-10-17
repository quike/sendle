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

  func makeModel() -> SettingsViewModel {
    SettingsViewModel(
      configure: ConfigureEmail(settings: settings, secrets: secrets),
      sendTest: SendTestEmail(
        settings: settings, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      settings: settings, loginItem: loginItem, converter: converter)
  }

  /// A model with nothing saved yet, as before the first setup.
  func makeUnconfiguredModel() -> SettingsViewModel {
    let empty = InMemorySettingsStore()
    return SettingsViewModel(
      configure: ConfigureEmail(settings: empty, secrets: MemorySecretStore()),
      sendTest: SendTestEmail(
        settings: empty, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      settings: empty, loginItem: loginItem, converter: converter)
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
}
