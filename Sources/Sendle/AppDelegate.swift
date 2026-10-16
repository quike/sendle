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
    let composition = Composition(loginItem: MainAppLoginItem())
    self.composition = composition
    if let folder = ProcessInfo.processInfo.environment[Snapshot.environmentKey] {
      Task {
        await Snapshot.render(composition, to: URL(filePath: folder, directoryHint: .isDirectory))
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
    button.attributedTitle =
      state.needsAttention
      ? NSAttributedString(
        string: "●",
        attributes: [
          .foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 7),
          .baselineOffset: 5,
        ])
      : NSAttributedString()
    button.toolTip = state.needsAttention ? "Sendle needs you" : "Sendle"
  }

  @objc private func statusItemClicked() {
    guard let button = statusItem?.button else { return }
    if NSApp.currentEvent?.type == .rightMouseUp {
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
