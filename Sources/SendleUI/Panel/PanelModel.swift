import CoreGraphics
import Foundation
import Observation
import SendleDomain

package enum PanelRoute: Equatable, Sendable {
  case library
  case setup
}

/// The panel's state above its screens: which one shows, the settings sheet, keys, fixes and the
/// menu bar icon.
@Observable @MainActor
public final class PanelModel {
  package static let fullDiskAccessURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  package let library: LibraryViewModel
  package let setup: SetupViewModel
  package let settings: SettingsViewModel
  package let covers: CoverStore
  package private(set) var route = PanelRoute.library
  package private(set) var isShowingSettings = false
  package private(set) var notice: Problem?
  /// Bumped by ⌘F; the search field takes the keyboard when it changes.
  package private(set) var searchFocusRequests = 0
  /// The status item's centre, measured from the card's left edge, where the arrow points.
  public var arrowX: CGFloat = 200

  @ObservationIgnored private weak var system: (any SystemActions)?
  @ObservationIgnored private var accessWatch: Task<Void, Never>?
  /// Bumped by every open and close, so an opening that a newer one replaced leaves the state alone.
  @ObservationIgnored private var session = 0

  public init(
    library: LibraryViewModel,
    setup: SetupViewModel,
    settings: SettingsViewModel,
    covers: CoverStore
  ) {
    self.library = library
    self.setup = setup
    self.settings = settings
    self.covers = covers
  }

  /// The shell owns the panel, so it's attached after both exist.
  public func attach(_ system: any SystemActions) {
    self.system = system
  }

  public var statusItem: StatusItemState {
    let kindlePluggedIn = library.destinations.contains { $0.kind == .usb }
    let libraryFailed = if case .failed = library.state { true } else { false }
    return StatusItemState(
      symbolName: kindlePluggedIn ? "books.vertical.fill" : "books.vertical",
      needsAttention: notice != nil || libraryFailed)
  }

  package var isWaitingForAccess: Bool { accessWatch != nil }

  // MARK: Lifecycle

  /// Reads the library once, so the red dot can ask for access before the panel ever opens.
  public func launch() async {
    await library.start()
    await library.reload()
  }

  /// Library access is checked again every time the panel opens. The shell cancels this when the
  /// panel closes before it finishes; a newer open or close then owns the state.
  public func panelDidOpen() async {
    session += 1
    let opened = session
    await library.appear()
    guard opened == session else { return }
    guard !Task.isCancelled else { return panelDidClose() }
    if library.needsAccess {
      showSetup(at: .libraryAccess)
    } else if route == .setup, setup.step == .libraryAccess {
      await libraryAccessArrived()
    }
  }

  public func panelDidClose() {
    session += 1
    library.disappear()
    accessWatch?.cancel()
    accessWatch = nil
  }

  public func show(notice: Problem) {
    self.notice = notice
  }

  // MARK: Setup

  package func showSetup(at step: SetupStep) {
    route = .setup
    setup.begin(at: step)
    if step == .libraryAccess { watchForAccess() }
  }

  package func finishSetup() async {
    guard await setup.finish() else { return }
    await library.refreshSettings()
    route = .library
  }

  /// The Kindle email can be set up later from its chip.
  package func skipSetup() {
    route = .library
  }

  package func revealApp() {
    system?.revealApp()
  }

  /// A click on a book takes the keyboard back from the search field, so arrows reach the library.
  package func click(_ id: BookID, _ kind: ClickKind) {
    system?.endEditing()
    library.click(id, kind)
  }

  private func watchForAccess() {
    guard accessWatch == nil else { return }
    accessWatch = Task { [weak self] in
      guard let granted = await self?.setup.waitForLibraryAccess(), granted, !Task.isCancelled
      else { return }
      await self?.libraryAccessArrived()
    }
  }

  private func libraryAccessArrived() async {
    accessWatch = nil
    if setup.accessGranted(emailConfigured: library.hasKindleEmail) { route = .library }
  }

  // MARK: Settings sheet

  package func openSettings(_ section: SettingsSection = .kindle) async {
    await settings.open(at: section)
    isShowingSettings = true
  }

  package func closeSettings() {
    isShowingSettings = false
  }

  package func saveSettings() async {
    guard await settings.save() else { return }
    await library.refreshSettings()
    isShowingSettings = false
  }

  // MARK: Keys

  /// Esc closes the innermost thing: the sheet, then the selection, then the panel.
  package func escape() {
    if isShowingSettings {
      isShowingSettings = false
    } else if route == .library, library.clearSelection() {
      return
    } else {
      system?.closePanel()
    }
  }

  /// True when the key was used, so the shell swallows it.
  public func handle(_ key: KeyInput) -> Bool {
    guard let command = key.panelCommand else { return false }
    switch command {
    case .escape:
      escape()
    case .openSettings:
      if !isShowingSettings { Task { await openSettings() } }
    case .move, .selectAll, .layout, .focusSearch:
      guard route == .library, !isShowingSettings else { return false }
      runLibraryCommand(command)
    }
    return true
  }

  private func runLibraryCommand(_ command: PanelCommand) {
    switch command {
    case .move(let direction): library.move(direction)
    case .selectAll: library.selectAll()
    case .layout(let layout): Task { await library.setLayout(layout) }
    case .focusSearch: searchFocusRequests += 1
    case .escape, .openSettings: break
    }
  }

  // MARK: Fixes

  package func perform(_ action: FixAction) async {
    switch action {
    case .openPrivacySettings:
      if let url = URL(string: Self.fullDiskAccessURL) { system?.open(url) }
    case .openSettings(let section):
      await openSettings(section)
    case .useDestination(let kind):
      await library.activate(kind)
    case .openURL(let url):
      system?.open(url)
    case .retry:
      await library.reload()
    }
  }

  package func performNoticeFix() async {
    let action = notice?.fix?.action
    notice = nil
    if let action { await perform(action) }
  }

  package func dismissNotice() {
    notice = nil
  }
}
