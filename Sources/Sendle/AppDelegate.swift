import AppKit
import Observation
import SendlePersistence
import SendleUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var composition: Composition?
  private var panel: PanelController?
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let snapshotFolder = ProcessInfo.processInfo.environment[Snapshot.environmentKey]
    if snapshotFolder != nil { Snapshot.requireDataDirectory() }
    let kindles = snapshotFolder.map { _ in SnapshotKindles(mockRoot: Snapshot.writeMockKindle()) }
    let remover = snapshotFolder.map { _ in SnapshotKindleRemover() }
    let kindleLibrary = remover.map {
      SnapshotKindleLibrary(cacheDirectory: DataDirectory.url(), remover: $0)
    }
    let catalogue = snapshotFolder.map { _ in SnapshotCatalogue() }
    let composition = Composition(
      loginItem: MainAppLoginItem(), channels: snapshotFolder.map { _ in SnapshotChannels() },
      kindles: kindles, kindleLibrary: kindleLibrary, remover: remover,
      catalogues: catalogue.map { [$0] })
    self.composition = composition
    if let folder = snapshotFolder, let kindles, let kindleLibrary, let catalogue {
      Task {
        await Snapshot.render(
          composition, kindles: kindles, kindleLibrary: kindleLibrary, catalogue: catalogue,
          to: URL(filePath: folder, directoryHint: .isDirectory))
        NSApp.terminate(nil)
      }
      return
    }
    let panel = PanelController(model: composition.panel)
    composition.panel.attach(panel)
    self.panel = panel
    makeStatusItem()
    Task { await composition.launch() }
  }

  /// Quitting in the middle of a run asks first: the books not sent yet would be lost. A delete
  /// from the Kindle that Undo could still take back becomes final before Sendle quits.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model = composition?.panel else { return .terminateNow }
    if let warning = model.queue.quitWarning {
      panel?.hide()
      NSApp.activate()
      let alert = NSAlert()
      alert.messageText = warning.title
      alert.informativeText = warning.message ?? ""
      alert.addButton(withTitle: "Keep sending")
      alert.addButton(withTitle: "Quit")
      guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
    }
    guard model.hasPendingKindleDelete else { return .terminateNow }
    Task {
      await model.prepareToQuit()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  // MARK: Status item

  private func makeStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    item.button?.imagePosition = .imageLeading
    statusItem = item
    followStatus()
  }

  /// Redraws the icon whenever the state it shows changes.
  private func followStatus() {
    guard let model = composition?.panel else { return }
    withObservationTracking {
      render(model.statusItem)
    } onChange: { [weak self] in
      Task { @MainActor in self?.followStatus() }
    }
  }

  private func render(_ state: StatusItemState) {
    guard let button = statusItem?.button else { return }
    let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: "Sendle")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
    image?.isTemplate = true
    button.image = image
    let title = NSMutableAttributedString()
    if let progress = state.progress {
      title.append(
        NSAttributedString(
          string: " \(progress)",
          attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]))
    }
    if state.needsAttention {
      title.append(
        NSAttributedString(
          string: "●",
          attributes: [
            .foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 7),
            .baselineOffset: 5,
          ]))
    }
    button.attributedTitle = title
    button.toolTip = state.needsAttention ? "Sendle needs you" : "Sendle"
  }

  /// A right click or a Control-click opens the menu, as on any menu bar item.
  @objc private func statusItemClicked() {
    guard let button = statusItem?.button else { return }
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      showMenu()
    } else {
      panel?.toggle(below: button)
    }
  }

  private func showMenu() {
    panel?.hide()
    let menu = NSMenu()
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    menu.addItem(withTitle: "Reveal Sendle Data", action: #selector(revealData), keyEquivalent: "")
      .target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "About Sendle", action: #selector(showAbout), keyEquivalent: "")
      .target = self
    menu.addItem(
      withTitle: "Quit Sendle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem?.menu = menu
    statusItem?.button?.performClick(nil)
    statusItem?.menu = nil
  }

  @objc private func openSettings() {
    guard let button = statusItem?.button, let panel, let model = composition?.panel else { return }
    if !panel.isVisible { panel.show(below: button) }
    Task { await model.openSettings() }
  }

  @objc private func revealData() {
    let folder = DataDirectory.url()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([folder])
  }

  @objc private func showAbout() {
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(nil)
  }
}
