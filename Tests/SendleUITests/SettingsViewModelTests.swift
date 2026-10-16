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

  func makeModel() -> SettingsViewModel {
    SettingsViewModel(
      configure: ConfigureEmail(settings: settings, secrets: secrets),
      sendTest: SendTestEmail(
        settings: settings, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      settings: settings, loginItem: loginItem)
  }

  /// A model with nothing saved yet, as before the first setup.
  func makeUnconfiguredModel() -> SettingsViewModel {
    let empty = InMemorySettingsStore()
    return SettingsViewModel(
      configure: ConfigureEmail(settings: empty, secrets: MemorySecretStore()),
      sendTest: SendTestEmail(
        settings: empty, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      settings: empty, loginItem: loginItem)
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
}
