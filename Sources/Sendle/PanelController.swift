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
  /// A file picker is open, so losing the key window must not close the panel.
  private var isChoosingFile = false
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
    let host = NSHostingView(rootView: PanelView(panel: model))
    // The window's frame is placed here, around a card that must not move.
    host.sizingOptions = []
    window.contentView = host
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
    let placement = PanelPlacement(below: anchor, in: visible)
    model.railSide = placement.side
    model.arrowX = placement.arrowX
    window.setFrame(placement.window, display: true)

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
    if !isChoosingFile { hide() }
  }

  /// Text fields keep their editing keys; everything else goes to the panel's shortcuts. A field
  /// composing text with an input method keeps every key, because Return commits the composition.
  private func handle(_ event: NSEvent) -> Bool {
    if (window.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
    let isEditingText = window.firstResponder is NSText
    if isEditingText,
      let command = TextEditingCommand(
        characters: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags)
    {
      return window.firstResponder?.tryToPerform(command.selector, with: nil) ?? false
    }
    guard
      let key = KeyInput(
        keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
        modifierFlags: event.modifierFlags, isEditingText: isEditingText,
        isRepeat: event.isARepeat)
    else { return false }
    return model.handle(key)
  }
}

extension TextEditingCommand {
  fileprivate var selector: Selector {
    switch self {
    case .cut: #selector(NSText.cut(_:))
    case .copy: #selector(NSText.copy(_:))
    case .paste: #selector(NSText.paste(_:))
    case .selectAll: #selector(NSText.selectAll(_:))
    case .undo: Selector(("undo:"))
    case .redo: Selector(("redo:"))
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

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func chooseProgram() async -> URL? {
    guard !isChoosingFile else { return nil }
    isChoosingFile = true
    defer {
      isChoosingFile = false
      // A click elsewhere may have closed the panel while the picker was open.
      if isVisible { window.makeKeyAndOrderFront(nil) }
    }
    let picker = NSOpenPanel()
    picker.canChooseFiles = true
    picker.canChooseDirectories = false
    picker.allowsMultipleSelection = false
    picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(
      path: ".cargo/bin", directoryHint: .isDirectory)
    picker.message = "Choose the boko program."
    picker.prompt = "Use"
    // Above the panel, which floats at the pop-up menu level.
    picker.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    NSApp.activate()
    let response = await withCheckedContinuation { continuation in
      picker.begin { continuation.resume(returning: $0) }
    }
    return response == .OK ? picker.url : nil
  }
}
