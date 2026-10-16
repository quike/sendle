import AppKit
import SendleDomain
import SendleUI
import SwiftUI

/// `SENDLE_SNAPSHOT_DIR=<folder>` writes a PNG of each panel screen there and quits, to look at
/// the UI without clicking through it. It saves layout choices, so pair it with `SENDLE_DATA_DIR`.
@MainActor
enum Snapshot {
  static let environmentKey = "SENDLE_SNAPSHOT_DIR"

  static func render(_ composition: Composition, to folder: URL) async {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let panel = composition.panel
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: PanelView.windowSize), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: PanelView(panel: panel))
    await composition.launch()
    await panel.panelDidOpen()
    if panel.route == .library {
      for layout in LibraryLayout.allCases {
        await panel.library.setLayout(layout)
        await write(window, "library-\(layout.rawValue).png", to: folder)
      }
      panel.library.selectAll()
      await write(window, "library-selected.png", to: folder)
      _ = panel.library.clearSelection()
    }
    for step in SetupStep.allCases {
      panel.showSetup(at: step)
      panel.panelDidClose()
      await write(window, "setup-\(step.rawValue + 1).png", to: folder)
    }
    for section in SettingsSection.allCases {
      await panel.openSettings(section)
      await write(window, "settings-\(section.rawValue).png", to: folder)
    }
  }

  /// Waits for covers and animations, then draws the window's content.
  private static func write(_ window: NSWindow, _ name: String, to folder: URL) async {
    try? await Task.sleep(for: .milliseconds(700))
    guard let view = window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(
      to: folder.appending(path: name))
  }
}
