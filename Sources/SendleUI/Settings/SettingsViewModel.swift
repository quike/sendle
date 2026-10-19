import Foundation
import Observation
import SendleDomain

/// The settings sheet: a front page of sections with a search, and a page per section
/// (spec §3.5).
@Observable @MainActor
public final class SettingsViewModel {
  /// The open page; nil is the front page.
  package var section: SettingsSection?
  package var query = ""
  /// The setting a search result led to, which its page marks for a moment.
  package private(set) var highlighted: SettingsItem?
  package let form: EmailForm
  package private(set) var launchAtLogin = LoginItemStatus.disabled
  package private(set) var launchAtLoginError: String?
  package private(set) var jumpBar = JumpBarStyle.full
  package private(set) var controls = ControlsStyle.attached
  package private(set) var showsFormat = true
  package private(set) var showsLogs = false
  package private(set) var kindleAddresses: [KindleEmail] = []
  package private(set) var activeKindleAddress: KindleEmail?
  package var newKindleAddress = ""
  package private(set) var kindleAddressError: String?
  package private(set) var kindleAddressWarning: String?
  /// boko, when Sendle can run it.
  package private(set) var boko: URL?
  /// The boko the user chose, found or not.
  package private(set) var chosenBoko: URL?
  package private(set) var bokoError: String?
  /// Told whenever a choice the panel shows changes: the controls, the A–Z bar, formats, logs,
  /// the Kindle address, boko.
  @ObservationIgnored package var onChange: (@MainActor () async -> Void)?
  @ObservationIgnored private var unmark: Task<Void, Never>?
  /// The email setup as saved; the form may hold edits that aren't.
  private var savedEmail: EmailSettings?

  private let settings: any SettingsStore
  private let addresses: ManageKindleAddresses
  private let chooseTool: ChooseConverterTool
  private let loginItem: any LoginItem
  private let converter: any FormatConverter & ToolChoice
  private let log: any ActivityLog

  public init(
    configure: ConfigureEmail,
    sendTest: SendTestEmail,
    addresses: ManageKindleAddresses,
    chooseTool: ChooseConverterTool,
    settings: any SettingsStore,
    loginItem: any LoginItem,
    converter: any FormatConverter & ToolChoice,
    log: any ActivityLog = NoActivityLog()
  ) {
    form = EmailForm(configure: configure, sendTest: sendTest)
    self.addresses = addresses
    self.chooseTool = chooseTool
    self.settings = settings
    self.loginItem = loginItem
    self.converter = converter
    self.log = log
  }

  /// Reads what the panel needs before Settings ever opens, such as whether logs are on.
  package func start() async {
    let saved = await settings.load()
    jumpBar = saved.jumpBar
    controls = saved.controls
    showsFormat = saved.showsFormat
    showsLogs = saved.showsLogs
  }

  /// Starts from what is saved, so edits that were never saved are gone.
  package func open(at section: SettingsSection?) async {
    self.section = section
    query = ""
    highlighted = nil
    let saved = await settings.load()
    form.fill(from: saved.email)
    show(saved)
    newKindleAddress = ""
    kindleAddressError = nil
    kindleAddressWarning = nil
    launchAtLogin = loginItem.status
    launchAtLoginError = nil
    readBoko()
    bokoError = nil
  }

  /// Catches up with a setup saved from elsewhere, such as by a test email.
  package func reload() async {
    show(await settings.load())
  }

  package var hasEmailSetup: Bool { savedEmail != nil }

  // MARK: Pages and search

  package func show(_ section: SettingsSection?) {
    self.section = section
    highlighted = nil
  }

  package var results: [SettingsItem] {
    SettingsSearch.results(for: query)
  }

  /// Opens the page that holds `item` and marks it.
  package func choose(_ item: SettingsItem) {
    query = ""
    section = item.section
    highlighted = item
    unmark?.cancel()
    unmark = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled, self?.highlighted == item else { return }
      self?.highlighted = nil
    }
  }

  /// What each row of the front page says about its section.
  package func summary(of section: SettingsSection) -> String {
    switch section {
    case .general:
      let login =
        switch launchAtLogin {
        case .enabled: "Opens at login"
        case .requiresApproval: "Waiting for approval"
        case .disabled, .unavailable: "Doesn't open at login"
        }
      let controls = controls == .attached ? "Attached" : "Floating"
      let bar = jumpBar == .full ? "Full" : "Compact"
      let formats = showsFormat ? "on" : "off"
      let logs = showsLogs ? "on" : "off"
      return
        "\(login) · Controls: \(controls) · A–Z bar: \(bar) · Formats \(formats) · Logs \(logs)"
    case .kindle:
      guard let active = activeKindleAddress else { return "Not set up" }
      let others = kindleAddresses.count - 1
      return others > 0 ? "\(active.rawValue) · \(others + 1) saved" : active.rawValue
    case .sender:
      guard let savedEmail else { return "Not set up" }
      return "\(savedEmail.provider.pickerName) · \(savedEmail.senderAddress)"
    case .usb:
      return bokoTitle
    }
  }

  /// The setup is checked as a whole; when the fields to fix are in the other section, go there.
  package func save() async -> Bool {
    guard await form.save() else {
      let sections = Set(
        form.issues.map { $0 == .invalidKindleAddress ? SettingsSection.kindle : .sender })
      if !sections.isEmpty, let section, !sections.contains(section) {
        self.section = sections.contains(.kindle) ? .kindle : .sender
      }
      return false
    }
    show(await settings.load())
    return true
  }

  // MARK: General

  package func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try loginItem.setEnabled(enabled)
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = "Couldn't change this: \(error.localizedDescription)"
      log.error(.app, "Couldn't turn launch at login \(enabled ? "on" : "off"): \(error)")
    }
    launchAtLogin = loginItem.status
  }

  package var launchAtLoginNote: String? {
    switch launchAtLogin {
    case .requiresApproval: "Approve Sendle in System Settings › General › Login Items."
    case .unavailable: "Launch at login works once Sendle runs as an app."
    case .enabled, .disabled: nil
    }
  }

  package func setJumpBar(_ style: JumpBarStyle) async {
    jumpBar = style
    await store { $0.jumpBar = style }
  }

  package func setControls(_ style: ControlsStyle) async {
    controls = style
    await store { $0.controls = style }
  }

  package func setShowsFormat(_ shows: Bool) async {
    showsFormat = shows
    await store { $0.showsFormat = shows }
  }

  package func setShowsLogs(_ shows: Bool) async {
    showsLogs = shows
    await store { $0.showsLogs = shows }
  }

  // MARK: Kindle

  /// Saves the typed address and makes it the active one.
  @discardableResult
  package func addKindleAddress() async -> Bool {
    do throws(KindleAddressError) {
      let warnings = try await addresses.add(newKindleAddress)
      kindleAddressWarning =
        warnings.isEmpty
        ? nil : "This isn't a @kindle.com address. Check it under Devices in your Amazon account."
      kindleAddressError = nil
      newKindleAddress = ""
    } catch {
      kindleAddressError = Self.message(for: error)
      return false
    }
    await reloadAddresses()
    return true
  }

  package func activate(_ address: KindleEmail) async {
    do throws(KindleAddressError) {
      try await addresses.activate(address)
      kindleAddressError = nil
    } catch {
      kindleAddressError = Self.message(for: error)
    }
    await reloadAddresses()
  }

  package func remove(_ address: KindleEmail) async {
    do throws(KindleAddressError) {
      try await addresses.remove(address)
      kindleAddressError = nil
    } catch {
      kindleAddressError = Self.message(for: error)
    }
    await reloadAddresses()
  }

  // MARK: USB

  package func chooseBoko(_ tool: URL) async {
    do throws(ConverterChoiceError) {
      try await chooseTool(tool)
      bokoError = nil
    } catch {
      bokoError =
        switch error {
        case .notExecutable: "\(tool.lastPathComponent) isn't a program Sendle can run."
        case .storage(let failure): "Couldn't save the choice: \(failure.detail)"
        }
    }
    readBoko()
    await onChange?()
  }

  package func resetBoko() async {
    do throws(ConverterChoiceError) {
      try await chooseTool(nil)
      bokoError = nil
    } catch {
      if case .storage(let failure) = error {
        bokoError = "Couldn't save the choice: \(failure.detail)"
      }
    }
    readBoko()
    await onChange?()
  }

  package var bokoTitle: String {
    boko == nil ? "boko not found" : "boko found"
  }

  package var bokoNote: String {
    if boko == nil, let chosenBoko {
      return "Sendle looks only where you chose: \(chosenBoko.path). Choose it again, or reset "
        + "to look in the usual folders."
    }
    return boko == nil
      ? "Your Kindle can't read EPUB, so Sendle converts EPUBs with boko before copying them. "
        + "Until it's installed, PDFs go over USB and EPUBs go by email."
      : "EPUBs are converted to AZW3 before they're copied to your Kindle."
  }

  // MARK: Private

  private func show(_ saved: AppSettings) {
    jumpBar = saved.jumpBar
    controls = saved.controls
    showsFormat = saved.showsFormat
    showsLogs = saved.showsLogs
    savedEmail = saved.email
    kindleAddresses = saved.savedKindleAddresses
    activeKindleAddress = saved.email.flatMap { saved.savedSpelling(of: $0.kindleAddress) }
  }

  private func reloadAddresses() async {
    show(await settings.load())
    if let activeKindleAddress { form.kindleAddress = activeKindleAddress.rawValue }
    await onChange?()
  }

  private func readBoko() {
    boko = converter.toolURL
    chosenBoko = converter.chosenTool
  }

  private func store(_ change: @escaping @Sendable (inout AppSettings) -> Void) async {
    do throws(StorageError) {
      try await settings.update(change)
    } catch {
      log.error(.app, "Couldn't save a setting: \(error.detail)")
    }
    await onChange?()
  }

  private static func message(for error: KindleAddressError) -> String {
    switch error {
    case .invalidAddress: "Enter your Kindle's Send to Kindle address, like name@kindle.com."
    case .notConfigured: "Set up your Kindle email first."
    case .active: "Make another address active before removing this one."
    case .storage(let failure): "Couldn't save the addresses: \(failure.detail)"
    }
  }
}
