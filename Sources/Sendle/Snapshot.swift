import AppKit
import SendleDomain
import SendleKindleUSB
import SendlePersistence
import SendleUI
import SwiftUI
import os

/// `SENDLE_SNAPSHOT_DIR=<folder>` writes a PNG of each panel screen there and quits, to look at
/// the UI without clicking through it. It saves layout choices and records a fake send, so it
/// needs `SENDLE_DATA_DIR`. Its Kindle is a mock tree under that folder.
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

  /// Writes the mock Kindle's files under the data folder and returns where they are.
  static func writeMockKindle() -> URL {
    let root = DataDirectory.url().appending(path: "mock-kindle", directoryHint: .isDirectory)
    do {
      try MockKindle.write(to: root)
    } catch {
      FileHandle.standardError.write(Data("Couldn't write the mock Kindle: \(error)\n".utf8))
      exit(1)
    }
    return root
  }

  static func render(
    _ composition: Composition, kindles: SnapshotKindles, kindleLibrary: SnapshotKindleLibrary,
    to folder: URL
  ) async {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let panel = composition.panel
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: PanelView.windowSize), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: PanelView(panel: panel))
    await write(window, "library-loading.png", to: folder)
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
      await panel.library.setLayout(.grid)
      panel.library.isRailHovered = true
      await write(window, "library-az-compact-hover.png", to: folder)
      panel.library.isRailHovered = false
      await panel.settings.setJumpBar(.full)
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
    await renderKindle(panel, window: window, kindles: kindles, library: kindleLibrary, to: folder)
    select(["A004", "A013"], in: panel)
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
    await panel.library.activate(.usb(kindles.volume(named: "Kindle Oasis")))
    await write(window, "library-usb-3.png", to: folder)
  }

  /// Plugs in the mock Kindle, holds its first read at the third book, then lets it finish
  /// and shows what the library and the Kindle side make of it.
  private static func renderKindle(
    _ panel: PanelModel, window: NSWindow, kindles: SnapshotKindles,
    library kindleLibrary: SnapshotKindleLibrary, to folder: URL
  ) async {
    let saved = panel.library.layout
    kindleLibrary.hold()
    kindles.plugIn()
    await panel.library.activate(.usb)
    await until { panel.kindle.state == .reading(done: 3, total: 10) }
    panel.showSide(.kindle)
    await write(window, "kindle-reading.png", to: folder)
    await panel.library.setLayout(.grid)
    await write(window, "kindle-reading-grid.png", to: folder)
    await panel.library.setLayout(saved)
    kindleLibrary.release()
    await until { panel.kindle.state == .loaded && panel.kindle.matches != nil }

    panel.showSide(.library)
    await write(window, "library-usb.png", to: folder)
    await panel.library.setSort(.title)
    for layout in [LibraryLayout.grid, .list] {
      await panel.library.setLayout(layout)
      await write(window, "library-kindle-\(layout.rawValue).png", to: folder)
    }
    for filter in panel.library.filters {
      panel.library.filter = filter
      let name = filter == .onKindle ? "library-on-kindle" : "library-scope-\(filter.rawValue)"
      await write(window, "\(name).png", to: folder)
    }
    panel.library.filter = .all
    panel.hoveredChip = kindles.volume(named: "Kindle")
    await write(window, "chip-eject-hover.png", to: folder)
    panel.hoveredChip = nil
    await panel.library.setSort(.recent)
    await panel.library.setLayout(saved)

    panel.showSide(.kindle)
    for layout in LibraryLayout.allCases {
      await panel.library.setLayout(layout)
      await write(window, "kindle-\(layout.rawValue).png", to: folder)
    }
    await panel.library.setLayout(.list)
    panel.kindle.scope = .notInLibrary
    await write(window, "kindle-not-in-library.png", to: folder)
    panel.kindle.scope = .all
    await panel.library.setLayout(saved)
    panel.showSide(.library)

    await panel.library.setSort(.title)
    select(["A000", "A009"], in: panel)
    await panel.sendSelection()
    await write(window, "duplicates-sure.png", to: folder)
    panel.choose(.skip)
    await write(window, "duplicates-maybe.png", to: folder)
    panel.cancelReview()
    for (id, name) in [("A031", "duplicates-pdf-size"), ("A022", "duplicates-format")] {
      select([id], in: panel)
      await panel.sendSelection()
      await write(window, "\(name).png", to: folder)
      panel.cancelReview()
    }
    _ = panel.library.clearSelection()
    await panel.library.setSort(.recent)
  }

  private static func select(_ ids: [String], in panel: PanelModel) {
    for (index, id) in ids.enumerated() {
      panel.click(BookID(rawValue: id), index == 0 ? .plain : .toggle)
    }
  }

  /// Polls for up to five seconds, so a shot that waits for something that never comes still ends.
  private static func until(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(10))
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

/// Snapshot mode's Kindles: none at first, then "Kindle" at the mock tree and any others at
/// /Volumes paths that nothing is copied to.
final class SnapshotKindles: DestinationMonitor {
  private struct State {
    var volumes: [KindleVolume] = []
    var listeners: [AsyncStream<[KindleVolume]>.Continuation] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let mockRoot: URL

  init(mockRoot: URL) {
    self.mockRoot = mockRoot
  }

  func volumes() -> AsyncStream<[KindleVolume]> {
    AsyncStream { continuation in
      state.withLock {
        $0.listeners.append(continuation)
        continuation.yield($0.volumes)
      }
    }
  }

  func volume(named name: String) -> KindleVolume {
    KindleVolume(
      id: "/Volumes/\(name)", name: name,
      mountURL: name == "Kindle" ? mockRoot : URL(filePath: "/Volumes/\(name)"))
  }

  func plugIn(_ names: [String] = ["Kindle"]) {
    let volumes = names.map(volume(named:))
    state.withLock { state in
      state.volumes = volumes
      for listener in state.listeners { listener.yield(volumes) }
    }
  }
}

/// Reads the mock Kindle as the real library would, and can stop a read at its third book.
final class SnapshotKindleLibrary: KindleLibrary {
  private struct Gate {
    var isHolding = false
    var waiter: CheckedContinuation<Void, Never>?
  }

  private let reader: USBKindleLibrary
  private let gate = OSAllocatedUnfairLock(initialState: Gate())

  init(cacheDirectory: URL) {
    reader = USBKindleLibrary(cacheDirectory: cacheDirectory)
  }

  /// The next read waits at its third book until `release()`.
  func hold() {
    gate.withLock { $0.isHolding = true }
  }

  func release() {
    let waiter = gate.withLock { gate -> CheckedContinuation<Void, Never>? in
      gate.isHolding = false
      defer { gate.waiter = nil }
      return gate.waiter
    }
    waiter?.resume()
  }

  func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing {
    try await reader.listing(of: volume) { [self] done, total in
      await progress(done, total)
      if done == 3 { await waitWhileHeld() }
    }
  }

  func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover {
    await reader.cover(of: book, on: volume, maxPixel: maxPixel)
  }

  private func waitWhileHeld() async {
    await withCheckedContinuation { continuation in
      let isHeld = gate.withLock { gate in
        if gate.isHolding { gate.waiter = continuation }
        return gate.isHolding
      }
      if !isHeld { continuation.resume() }
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
