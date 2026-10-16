import AppKit
import SendleUI
import SwiftUI

private final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// The borderless card under the menu bar icon (house-control's recipe). The SwiftUI view draws
/// the card, its arrow and its shadow on a clear window.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
  private let model: PanelModel
  private let window: FloatingPanel
  private var outsideClickMonitor: Any?
  private var keyMonitor: Any?
  private var lastHide = Date.distantPast
  private var opening: Task<Void, Never>?
  private(set) var isVisible = false

  init(model: PanelModel) {
    self.model = model
    window = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: PanelView.windowSize),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    super.init()
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .popUpMenu
    window.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
    ]
    window.isMovable = false
    window.hidesOnDeactivate = false
    window.animationBehavior = .none
    window.delegate = self
    window.contentView = NSHostingView(rootView: PanelView(panel: model))
    window.alphaValue = 0
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let isUsed = MainActor.assumeIsolated {
        guard let self, event.window === self.window else { return false }
        return self.handle(event)
      }
      return isUsed ? nil : event
    }
  }

  func toggle(below button: NSStatusBarButton) {
    if isVisible { return hide() }
    // The click that dismissed the panel must not reopen it at once.
    if Date().timeIntervalSince(lastHide) < 0.25 { return }
    show(below: button)
  }

  func show(below button: NSStatusBarButton) {
    guard let buttonWindow = button.window else { return }
    let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let visible =
      (buttonWindow.screen ?? NSScreen.main)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let size = PanelView.windowSize
    let margin = PanelView.margins.leading
    let x = max(
      visible.minX + 4 - margin,
      min(anchor.midX - size.width / 2, visible.maxX - size.width + margin - 4))
    let y = anchor.minY - size.height + 3
    window.setFrame(
      NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    model.arrowX = anchor.midX - x.rounded() - margin

    isVisible = true
    window.makeKeyAndOrderFront(nil)
    // The panel opens with the library holding the keyboard; ⌘F or a click focuses search.
    window.makeFirstResponder(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      window.animator().alphaValue = 1
    }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.hide() }
    }
    opening = Task { [model] in await model.panelDidOpen() }
  }

  func hide() {
    guard isVisible else { return }
    isVisible = false
    lastHide = Date()
    opening?.cancel()
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      window.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isVisible else { return }
        self.window.orderOut(nil)
      }
    }
    model.panelDidClose()
  }

  func windowDidResignKey(_ notification: Notification) {
    hide()
  }

  /// Text fields keep their editing keys; everything else goes to the panel's shortcuts.
  private func handle(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    let isEditingText = window.firstResponder is NSText
    if isEditingText, flags.contains(.command), let action = Self.editingAction(for: event, flags) {
      return window.firstResponder?.tryToPerform(action, with: nil) ?? false
    }
    guard let key = Self.key(of: event) else { return false }
    return model.handle(KeyInput(key, command: flags == .command, isEditingText: isEditingText))
  }

  private static func key(of event: NSEvent) -> KeyInput.Key? {
    switch event.keyCode {
    case 53: .escape
    case 123: .left
    case 124: .right
    case 125: .down
    case 126: .up
    default: event.charactersIgnoringModifiers.map { .character($0) }
    }
  }

  /// A menu bar app has no Edit menu, so ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z reach text fields from here.
  private static func editingAction(for event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Selector?
  {
    switch (event.charactersIgnoringModifiers?.lowercased(), flags.contains(.shift)) {
    case ("x", false): #selector(NSText.cut(_:))
    case ("c", false): #selector(NSText.copy(_:))
    case ("v", false): #selector(NSText.paste(_:))
    case ("a", false): #selector(NSText.selectAll(_:))
    case ("z", false): Selector(("undo:"))
    case ("z", true): Selector(("redo:"))
    default: nil
    }
  }
}

extension PanelController: SystemActions {
  func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  func revealApp() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func closePanel() {
    hide()
  }

  func endEditing() {
    window.makeFirstResponder(nil)
  }
}
