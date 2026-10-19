import CoreGraphics
import Foundation
import Observation
import SendleDomain

package enum PanelRoute: Equatable, Sendable {
  case library
  case setup
  case queue
  case logs
}

/// Which of the library's two sides shows while a Kindle is plugged in.
package enum LibrarySide: Hashable, Sendable {
  case library
  case kindle
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
  package let queue: SendQueueViewModel
  package let logs: LogsViewModel
  package let kindle: KindleViewModel
  package private(set) var route = PanelRoute.library
  package private(set) var side = LibrarySide.library
  package private(set) var isShowingSettings = false
  package private(set) var notice: Problem?
  /// The Kindle being ejected, while it is.
  package private(set) var ejecting: KindleVolume?
  /// The Kindle chip under the pointer.
  package var hoveredChip: KindleVolume?
  /// Bumped by ⌘F; the search field takes the keyboard when it changes.
  package private(set) var searchFocusRequests = 0
  /// The status item's centre, measured from the card's left edge, where the arrow points.
  public var arrowX: CGFloat = 200

  @ObservationIgnored private weak var system: (any SystemActions)?
  @ObservationIgnored private let ejector: any KindleEjector
  @ObservationIgnored private var accessWatch: Task<Void, Never>?
  /// Where the logs go back to, and whether the settings sheet was over it.
  @ObservationIgnored private var beforeLogs = (route: PanelRoute.library, showedSettings: false)
  /// Bumped by every open and close, so an opening that a newer one replaced leaves the state alone.
  @ObservationIgnored private var session = 0

  public init(
    library: LibraryViewModel,
    setup: SetupViewModel,
    settings: SettingsViewModel,
    covers: CoverStore,
    queue: SendQueueViewModel,
    logs: LogsViewModel,
    kindle: KindleViewModel,
    ejector: any KindleEjector
  ) {
    self.library = library
    self.setup = setup
    self.settings = settings
    self.covers = covers
    self.queue = queue
    self.logs = logs
    self.kindle = kindle
    self.ejector = ejector
    library.reportProblem = { [weak self] problem in self?.show(notice: problem) }
    library.onKindleInputsChange = { [weak self] in self?.followKindle() }
    library.onSortChange = { [weak kindle] in kindle?.sort = $0 }
    kindle.onMatchesChange = { [weak library] in library?.showKindleMatches($0) }
    settings.onChange = { [weak library] in await library?.refreshSettings() }
    queue.onFinish = { [weak self] in await self?.refreshAfterSend() }
    queue.isKindleConnected = { [weak library] in library?.isKindlePluggedIn ?? false }
  }

  /// The shell owns the panel, so it's attached after both exist.
  public func attach(_ system: any SystemActions) {
    self.system = system
  }

  public var statusItem: StatusItemState {
    let libraryFailed = if case .failed = library.state { true } else { false }
    return StatusItemState(
      symbolName: library.isKindlePluggedIn ? "book.closed.fill" : "book.closed",
      needsAttention: notice != nil || libraryFailed || queue.needsAttention,
      progress: queue.progressLabel)
  }

  package var isWaitingForAccess: Bool { accessWatch != nil }

  /// The logs button shows while Settings › General › Show logs is on.
  package var showsLogs: Bool { settings.showsLogs }

  /// The side switch's labels, each with how many books it holds.
  package func switchTitle(_ side: LibrarySide) -> String {
    switch side {
    case .library:
      "Library · \(library.books.count)"
    case .kindle:
      kindle.listing.map { "On Kindle · \($0.books.count)" } ?? "On Kindle"
    }
  }

  /// The Kindle side only exists while a Kindle is plugged in.
  package func showSide(_ side: LibrarySide) {
    guard side == .library || library.isKindlePluggedIn else { return }
    self.side = side
  }

  // MARK: Lifecycle

  /// Reads the library once, so the red dot can ask for access before the panel ever opens.
  public func launch() async {
    await settings.start()
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
    if route == .logs { logs.start() }
    if library.needsAccess, route != .queue {
      showSetup(at: .libraryAccess)
    } else if route == .setup, setup.step == .libraryAccess {
      await libraryAccessArrived()
    }
  }

  public func panelDidClose() {
    session += 1
    library.disappear()
    logs.stop()
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

  /// A Kindle that goes takes its side with it.
  private func followKindle() {
    let volume = library.kindleVolume
    let books = library.books
    if volume == nil { side = .library }
    Task { await kindle.follow(volume, books: books) }
  }

  /// A USB send changed the Kindle, so it is read again; an email send only changed what the
  /// history says about the library.
  private func refreshAfterSend() async {
    await library.refreshHistory()
    if queue.destination?.kind == .usb {
      await kindle.refresh()
    } else {
      await kindle.rematch()
    }
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

  // MARK: Sending

  package func sendSelection() {
    send(library.selectedBooks)
  }

  package func quickSend(_ id: BookID) {
    guard let item = library.items.first(where: { $0.id == id && $0.canSend }) else { return }
    send([item.book])
  }

  /// Back to the library from a finished queue, which is then cleared.
  package func finishQueue() {
    guard !queue.isRunning else { return }
    queue.dismiss()
    route = .library
  }

  /// Retry sends the failed books again; using another destination goes back to the library.
  package func performQueueFix() async {
    guard let action = queue.summary?.fix?.action else { return }
    switch action {
    case .retry:
      queue.retryFailed()
    case .useDestination, .eject:
      finishQueue()
      await perform(action)
    case .openPrivacySettings, .openSettings, .openURL:
      await perform(action)
    }
  }

  private func send(_ books: [Book]) {
    guard let destination = library.activeDestination, !books.isEmpty, !queue.isRunning else {
      return
    }
    if case .usb(let volume) = destination, ejecting == volume { return }
    system?.endEditing()
    queue.send(books, to: destination)
    _ = library.clearSelection()
    route = .queue
  }

  // MARK: Logs

  /// Opens the logs over whatever shows; `subject` scrolls to the latest story of that send.
  package func openLogs(revealing subject: LogSubject? = nil) {
    if route != .logs { beforeLogs = (route, isShowingSettings) }
    isShowingSettings = false
    route = .logs
    logs.start()
    if let subject { logs.reveal(subject) } else { logs.showNewest() }
  }

  package func closeLogs() {
    logs.stop()
    route = beforeLogs.route
    isShowingSettings = beforeLogs.showedSettings
  }

  package func copyLogs() {
    system?.copy(logs.copyText())
  }

  // MARK: Ejecting

  /// A Kindle stays put while a book is being copied to it.
  package func canEject(_ volume: KindleVolume) -> Bool {
    ejecting == nil && !isCopying(to: volume)
  }

  /// Eject sits inside the Kindle's chip while the pointer is on it, and while it ejects.
  package func showsEject(in volume: KindleVolume) -> Bool {
    hoveredChip == volume || ejecting == volume
  }

  /// What VoiceOver offers on the chip; nil where Eject would be refused.
  package func ejectActionName(for volume: KindleVolume) -> String? {
    canEject(volume) ? "Eject \(volume.name)" : nil
  }

  private func isCopying(to volume: KindleVolume) -> Bool {
    queue.isRunning && queue.destination == .usb(volume)
  }

  /// The Kindle's chip goes away by itself once it is unmounted; a failure says why. A Kindle
  /// that is already gone is what Eject was for, so it says nothing.
  package func eject(_ volume: KindleVolume) async {
    guard library.destinations.contains(.usb(volume)) else { return }
    guard !isCopying(to: volume) else {
      return show(notice: ProblemPresenter.ejectWhileCopying(volume))
    }
    guard ejecting == nil else { return }
    ejecting = volume
    defer { ejecting = nil }
    do throws(EjectError) {
      try await ejector.eject(volume)
    } catch {
      show(notice: ProblemPresenter.problem(for: error, ejecting: volume))
    }
  }

  // MARK: Settings sheet

  /// Nil opens the front page.
  package func openSettings(_ section: SettingsSection? = nil) async {
    await settings.open(at: section)
    isShowingSettings = true
  }

  /// A test saves the setup first, so Settings and the library show what it may have changed.
  package func sendTest(from form: EmailForm) async {
    await form.sendTest()
    await settings.reload()
    await library.refreshSettings()
  }

  /// Lets the user point Sendle at a boko somewhere else.
  package func chooseBoko() async {
    guard let tool = await system?.chooseProgram() else { return }
    await settings.chooseBoko(tool)
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

  /// Esc closes the innermost thing: the sheet, a finished queue or a setup that can wait, the
  /// search, the selection, then the panel. A running queue keeps going behind a closed panel.
  package func escape() {
    if isShowingSettings {
      isShowingSettings = false
    } else if route == .logs {
      closeLogs()
    } else if route == .queue, !queue.isRunning {
      finishQueue()
    } else if route == .setup, !library.needsAccess {
      skipSetup()
    } else if route == .library, side == .kindle {
      if kindle.query.isEmpty { system?.closePanel() } else { kindle.query = "" }
    } else if route == .library, !library.query.isEmpty {
      library.query = ""
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
    case .confirm:
      return confirm()
    case .openSettings:
      if !isShowingSettings { Task { await openSettings() } }
    case .move(let direction):
      guard isOnLibraryBooks else { return false }
      system?.endEditing()
      library.move(direction)
    case .selectAll:
      guard isOnLibraryBooks else { return false }
      library.selectAll()
    case .layout(let layout):
      guard isOnLibrary else { return false }
      Task { await library.setLayout(layout) }
    case .focusSearch:
      guard isOnLibrary else { return false }
      searchFocusRequests += 1
    case .refresh:
      guard isOnLibrary, side == .kindle else { return false }
      Task { await kindle.refresh() }
    }
    return true
  }

  private var isOnLibrary: Bool { route == .library && !isShowingSettings }

  /// The library's books, which the Kindle side leaves unselectable.
  private var isOnLibraryBooks: Bool { isOnLibrary && side == .library }

  /// Return acts on the settings page, moves the setup on, sends the selection or leaves a finished
  /// queue.
  private func confirm() -> Bool {
    if isShowingSettings { return confirmSettings() }
    switch route {
    case .setup:
      switch setup.step {
      case .libraryAccess: return false
      case .kindleEmail: setup.continueToSender()
      case .sender: Task { await finishSetup() }
      }
    case .library:
      guard side == .library, !library.selection.isEmpty, library.canSend else { return false }
      sendSelection()
    case .queue:
      guard !queue.isRunning else { return false }
      finishQueue()
    case .logs:
      return false
    }
    return true
  }

  /// Return saves the sender, adds a typed Kindle address, or opens the first search result.
  private func confirmSettings() -> Bool {
    switch settings.section {
    case .sender? where settings.hasEmailSetup:
      Task { await saveSettings() }
    case .kindle? where !settings.newKindleAddress.isEmpty:
      Task { await settings.addKindleAddress() }
    case nil:
      guard let first = settings.results.first else { return false }
      settings.choose(first)
    default:
      return false
    }
    return true
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
    case .eject(let volume):
      await eject(volume)
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
