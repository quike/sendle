import AppKit
import SendleDomain
import SendlePersistence
import SendleUI
import SwiftUI
import os

/// `SENDLE_SNAPSHOT_DIR=<folder>` writes a PNG of each panel screen there and quits, to look at
/// the UI without clicking through it. It saves layout choices and records a fake send, so it
/// needs `SENDLE_DATA_DIR`.
@MainActor
enum Snapshot {
  static let environmentKey = "SENDLE_SNAPSHOT_DIR"

  /// Quits with an error unless `SENDLE_DATA_DIR` points away from the real data folder.
  static func requireDataDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    guard environment[DataDirectory.environmentKey]?.isEmpty ?? true else { return }
    FileHandle.standardError.write(
      Data(
        ("SENDLE_SNAPSHOT_DIR needs SENDLE_DATA_DIR, so the snapshot's fake sends stay out of "
          + "your real history.\n").utf8))
    exit(1)
  }

  static func render(_ composition: Composition, kindles: SnapshotKindles, to folder: URL) async {
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
      let layout = panel.library.layout
      await panel.library.setSort(.title)
      await panel.library.setLayout(.list)
      panel.library.jump(to: "M")
      await write(window, "library-az-full.png", to: folder)
      await panel.settings.setJumpBar(.compact)
      panel.library.drag(to: "P")
      await write(window, "library-az-compact.png", to: folder)
      panel.library.endDrag()
      await panel.settings.setJumpBar(.full)
      await panel.library.setLayout(.grid)
      panel.library.jump(to: "W")
      await write(window, "library-az-grid.png", to: folder)
      await panel.library.setSort(.recent)
      await panel.library.setLayout(layout)
      panel.library.selectAll()
      await write(window, "library-selected.png", to: folder)
      await panel.sendSelection()
      await write(window, "queue-sending.png", to: folder)
      panel.queue.cancel()
      await panel.queue.waitUntilFinished()
      await write(window, "queue-done.png", to: folder)
      panel.finishQueue()
    }
    for step in SetupStep.allCases {
      panel.showSetup(at: step)
      panel.panelDidClose()
      await write(window, "setup-\(step.rawValue + 1).png", to: folder)
    }
    await panel.openSettings()
    await write(window, "settings.png", to: folder)
    panel.settings.query = "pass"
    await write(window, "settings-search.png", to: folder)
    for section in SettingsSection.allCases {
      await panel.openSettings(section)
      await write(window, "settings-\(section.rawValue).png", to: folder)
    }
    panel.closeSettings()
    panel.skipSetup()
    kindles.plugIn()
    await panel.library.activate(.usb)
    await write(window, "library-usb.png", to: folder)
    panel.library.selectAll()
    await panel.sendSelection()
    await write(window, "queue-usb-sending.png", to: folder)
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    await write(window, "queue-usb-done.png", to: folder)
    panel.finishQueue()
    panel.openLogs()
    await write(window, "logs.png", to: folder)
    panel.closeLogs()
    kindles.plugIn(["Kindle", "Kindle Oasis", "Kindle Scribe"])
    await panel.library.activate(.usb(SnapshotKindles.volume(named: "Kindle Oasis")))
    await write(window, "library-usb-3.png", to: folder)
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

/// Snapshot mode's Kindle: none at first, then one at /Volumes/Kindle that nothing is copied to.
final class SnapshotKindles: DestinationMonitor {
  private struct State {
    var volumes: [KindleVolume] = []
    var listeners: [AsyncStream<[KindleVolume]>.Continuation] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func volumes() -> AsyncStream<[KindleVolume]> {
    AsyncStream { continuation in
      state.withLock {
        $0.listeners.append(continuation)
        continuation.yield($0.volumes)
      }
    }
  }

  static func volume(named name: String) -> KindleVolume {
    KindleVolume(id: "/Volumes/\(name)", name: name, mountURL: URL(filePath: "/Volumes/\(name)"))
  }

  func plugIn(_ names: [String] = ["Kindle"]) {
    state.withLock { state in
      state.volumes = names.map(Self.volume(named:))
      for listener in state.listeners { listener.yield(state.volumes) }
    }
  }
}

/// Snapshot mode sends nothing: to each destination, the first book goes at once and the next
/// stops at 62%.
struct SnapshotChannels: DeliveryChannelFactory {
  private let calls = OSAllocatedUnfairLock<[DestinationKind: Int]>(initialState: [:])

  func channel(for destination: Destination) async throws(SendFailure) -> any DeliveryChannel {
    let call = calls.withLock { calls in
      defer { calls[destination.kind, default: 0] += 1 }
      return calls[destination.kind, default: 0]
    }
    return SnapshotChannel(isFirst: call == 0)
  }
}

private struct SnapshotChannel: DeliveryChannel {
  let isFirst: Bool

  func deliver(
    _ file: PreparedFile,
    named baseName: String,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    await progress(isFirst ? 1 : 0.62)
    guard !isFirst else { return }
    try? await Task.sleep(for: .seconds(3_600))
    throw .cancelled
  }
}
