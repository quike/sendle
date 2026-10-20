import AppKit
import SendleDomain
import SendleKindleUSB
import SendlePersistence
import SendleUI
import SwiftUI
import os

/// `SENDLE_SNAPSHOT_DIR=<folder>` writes a PNG of each panel screen there and quits, to look at
/// the UI without clicking through it. It saves layout choices, records fake sends and edits some
/// books, so it needs `SENDLE_DATA_DIR`. Its Kindle is a mock tree under that folder.
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
      contentRect: NSRect(origin: .zero, size: PanelView.windowSize(margins: panel.windowMargins)),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: PanelView(panel: panel))
    // Attached until renderFloating floats them.
    await panel.settings.setControls(.attached)
    await write(window, "library-loading.png", to: folder)
    await composition.launch()
    await panel.panelDidOpen()
    if panel.route == .library {
      await renderHeight(panel, window: window, to: folder, sides: [.library], kindle: "no-kindle")
      for layout in LibraryLayout.allCases {
        await panel.library.setLayout(layout)
        await write(window, "library-\(layout.rawValue).png", to: folder)
      }
      let layout = panel.library.layout
      await panel.library.setSort(.title)
      await panel.library.setLayout(.list)
      panel.library.letterJump.jump(to: "M")
      await write(window, "library-az-full.png", to: folder)
      await panel.settings.setJumpBar(.compact)
      panel.library.letterJump.drag(to: "P")
      await write(window, "library-az-compact.png", to: folder)
      panel.library.letterJump.endDrag()
      await panel.library.setLayout(.grid)
      panel.library.letterJump.isHovered = true
      await write(window, "library-az-compact-hover.png", to: folder)
      panel.library.letterJump.isHovered = false
      await panel.settings.setJumpBar(.full)
      panel.library.letterJump.jump(to: "W")
      await write(window, "library-az-grid.png", to: folder)
      await renderGridEdges(panel, window: window, to: folder)
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
    await panel.openSettings(.sender)
    let provider = panel.settings.form.provider
    panel.settings.form.provider = .custom
    await write(window, "settings-sender-custom.png", to: folder)
    panel.settings.form.provider = provider
    panel.closeSettings()
    panel.skipSetup()
    await renderKindle(panel, window: window, kindles: kindles, library: kindleLibrary, to: folder)
    await renderFloating(panel, window: window, to: folder)
    select(["A004", "A013"], in: panel)
    await panel.sendSelection()
    await write(window, "queue-usb-sending.png", to: folder)
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    await write(window, "queue-usb-done.png", to: folder)
    panel.finishQueue()
    panel.openLogs()
    await write(window, "logs.png", to: folder)
    hover(panel, at: CGPoint(x: Theme.cardWidth - 118, y: 31))
    await write(window, "hover-copy-button.png", to: folder)
    hover(panel, at: nil)
    panel.closeLogs()
    kindles.plugIn(["Kindle", "Kindle Oasis", "Kindle Scribe"])
    await panel.library.activate(.usb(kindles.volume(named: "Kindle Oasis")))
    await write(window, "library-usb-3.png", to: folder)
    await renderDetails(panel, window: window, to: folder)
  }

  /// The edit sheet for an EPUB and for a PDF, and the list of books it edited, after the edits
  /// and the sends around them are saved through the stores. This runs last because it leaves
  /// them in the data folder.
  private static func renderDetails(
    _ panel: PanelModel, window: NSWindow, to folder: URL
  ) async {
    await seedEdits(in: panel)
    await panel.library.activate(DestinationKind.email)
    await panel.library.reload()
    await panel.library.setLayout(.list)
    await panel.library.setSort(.author)
    panel.library.letterJump.top = BookID(rawValue: "A002")
    await write(window, "library-edited.png", to: folder)

    await panel.openDetails(BookID(rawValue: "A010"))
    // Typing a new author is what brings up the writer checkbox.
    panel.bookDetails?.author = "Charles John Huffam Dickens"
    panel.bookDetails?.sortName = "Dickens, Charles J. H."
    await write(window, "edit-epub.png", to: folder)
    panel.closeDetails()

    await panel.openDetails(BookID(rawValue: "A022"))
    await write(window, "edit-pdf.png", to: folder)
    panel.closeDetails()
  }

  /// Renames Dickens, gives him a sort name and one of his books a year, a day ago. Two of his
  /// books were sent before that and one after.
  private static func seedEdits(in panel: PanelModel) async {
    let data = DataDirectory.url()
    let now = Date()
    let edited = now.addingTimeInterval(-86_400)
    let id = BookID(rawValue: "A010")
    guard let book = panel.library.books.first(where: { $0.id == id }) else { return }
    var draft = BookDetailsDraft(showing: book, fileValues: nil, otherBooks: 2)
    draft.author = "Charles J. H. Dickens"
    draft.sortName = "Dickens, Charles John Huffam"
    draft.year = "1861"
    let editor = EditBookDetails(
      store: JSONMetadataEditStore(directory: data), settings: nil, now: { edited })
    do throws(EditDetailsError) {
      try await editor.save(draft, for: book, fileValues: nil)
    } catch {
      FileHandle.standardError.write(Data("Couldn't seed the edits: \(error)\n".utf8))
    }
    let history = JSONSendHistoryStore(directory: data)
    for (sent, ago) in [("A002", 4 * 86_400.0), ("A010", 3 * 86_400.0), ("A020", 3 * 3_600.0)] {
      let record = SendRecord(
        bookID: BookID(rawValue: sent), destination: .email, date: now.addingTimeInterval(-ago),
        outcome: .sent)
      try? await history.append(record)
    }
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
    await panel.library.setSort(.title)
    for (layout, letter) in [(LibraryLayout.grid, "C"), (.list, "M")] {
      await panel.library.setLayout(layout)
      panel.kindle.letterJump.jump(to: letter)
      await write(window, "kindle-az-\(layout.rawValue).png", to: folder)
    }
    await panel.settings.setJumpBar(.compact)
    await panel.library.setLayout(.grid)
    panel.kindle.letterJump.isHovered = true
    await write(window, "kindle-az-compact.png", to: folder)
    panel.kindle.letterJump.isHovered = false
    await panel.settings.setJumpBar(.full)
    await panel.library.setSort(.recent)
    await panel.library.setLayout(saved)
    hover(panel, at: CGPoint(x: Theme.cardWidth - 29, y: 31))
    await write(window, "hover-header-button.png", to: folder)
    hover(panel, at: nil)
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

  /// The send bar and the A–Z bar on cards of their own: the send card, the A–Z card on the right
  /// and mirrored on the left, compact, on the Kindle side, and the setting that switches them.
  private static func renderFloating(_ panel: PanelModel, window: NSWindow, to folder: URL) async {
    await renderHeight(
      panel, window: window, to: folder, sides: [.library, .kindle], kindle: "kindle")
    let saved = panel.library.layout
    await renderMargins(panel, window: window, to: folder, prefix: "attached")
    await panel.settings.setControls(.floating)
    func place(_ side: RailSide) {
      panel.railSide = side
      window.setContentSize(PanelView.windowSize(margins: panel.windowMargins))
    }
    place(.trailing)
    await renderMargins(panel, window: window, to: folder, prefix: "floating")
    await panel.library.setLayout(.grid)
    select(["A004", "A013", "A020"], in: panel)
    await write(window, "floating-send-card.png", to: folder)
    _ = panel.library.clearSelection()

    await panel.library.setSort(.title)
    panel.library.letterJump.jump(to: "M")
    await write(window, "floating-az-right.png", to: folder)
    await panel.settings.setJumpBar(.compact)
    panel.library.letterJump.isHovered = true
    panel.library.letterJump.drag(to: "P")
    await write(window, "floating-az-compact.png", to: folder)
    panel.library.letterJump.endDrag()
    panel.library.letterJump.isHovered = false
    await panel.settings.setJumpBar(.full)

    place(.leading)
    await panel.library.setLayout(.list)
    panel.library.letterJump.jump(to: "D")
    select(["A004", "A013"], in: panel)
    await write(window, "floating-az-left.png", to: folder)
    _ = panel.library.clearSelection()

    panel.showSide(.kindle)
    await panel.library.setLayout(.grid)
    panel.kindle.letterJump.jump(to: "C")
    await write(window, "floating-kindle-left.png", to: folder)
    place(.trailing)
    await write(window, "floating-kindle-right.png", to: folder)
    panel.showSide(.library)
    await renderFloatingRails(panel, place: place, window: window, to: folder)

    await panel.openSettings(.general)
    await write(window, "floating-settings-general.png", to: folder)
    await panel.settings.setJumpBar(.compact)
    await write(window, "floating-settings-general-compact.png", to: folder)
    await panel.settings.setJumpBar(.full)
    panel.closeSettings()

    await panel.library.setSort(.recent)
    await panel.library.setLayout(saved)
    await panel.settings.setControls(.attached)
    place(.trailing)
  }

  /// The A–Z card on each side of the card, full and compact, on the library and the Kindle side.
  private static func renderFloatingRails(
    _ panel: PanelModel, place: (RailSide) -> Void, window: NSWindow, to folder: URL
  ) async {
    for (side, sideName) in [(LibrarySide.library, "library"), (.kindle, "kindle")] {
      panel.showSide(side)
      for style in [JumpBarStyle.full, .compact] {
        await panel.settings.setJumpBar(style)
        panel.library.letterJump.isHovered = style == .compact
        panel.kindle.letterJump.isHovered = style == .compact
        for (railSide, name) in [(RailSide.leading, "left"), (.trailing, "right")] {
          place(railSide)
          await write(
            window, "floating-az-\(name)-\(style.rawValue)-\(sideName).png", to: folder)
        }
      }
    }
    panel.library.letterJump.isHovered = false
    panel.kindle.letterJump.isHovered = false
    await panel.settings.setJumpBar(.full)
    panel.showSide(.library)
  }

  /// Each side and layout at rest, attached and floating, for the rows the card's height shows;
  /// then the grid on a card shrunk for a short screen.
  private static func renderHeight(
    _ panel: PanelModel, window: NSWindow, to folder: URL, sides: [LibrarySide], kindle: String
  ) async {
    let saved = panel.library.layout
    for controls in ControlsStyle.allCases {
      await panel.settings.setControls(controls)
      for side in sides {
        panel.showSide(side)
        for layout in LibraryLayout.allCases {
          await panel.library.setLayout(layout)
          // A new sort starts the books at the top.
          await panel.library.setSort(.title)
          await panel.library.setSort(.recent)
          let name = "height-\(kindle)-\(controls.rawValue)-\(side)-\(layout.rawValue)"
          await write(window, "\(name).png", to: folder)
        }
      }
    }
    panel.showSide(.library)
    await panel.library.setLayout(.grid)
    panel.cardSize.height = 520
    window.setContentSize(PanelView.windowSize(margins: panel.windowMargins, card: panel.cardSize))
    await write(window, "height-\(kindle)-floating-short.png", to: folder)
    panel.cardSize = Theme.cardSize
    window.setContentSize(PanelView.windowSize(margins: panel.windowMargins))
    await panel.settings.setControls(.attached)
    await panel.library.setLayout(saved)
  }

  /// Each side and layout scrolled to cut the books at the top and the bottom, and a lifted cover
  /// in the grid's first row at rest.
  private static func renderMargins(
    _ panel: PanelModel, window: NSWindow, to folder: URL, prefix: String
  ) async {
    let saved = panel.library.layout
    await panel.library.setSort(.title)
    for side in [LibrarySide.library, .kindle] {
      panel.showSide(side)
      for layout in LibraryLayout.allCases {
        await panel.library.setLayout(layout)
        if side == .library {
          let ids = panel.library.items.map(\.id)
          panel.library.letterJump.top = ids[ids.count / 3]
        } else {
          let ids = panel.kindle.items.map(\.id)
          panel.kindle.letterJump.top = ids[ids.count / 3]
        }
        // Past the side switch's slide, so only the new side's books are left to scroll.
        try? await Task.sleep(for: .seconds(1))
        scrollBooks(in: window, by: 37)
        await write(window, "\(prefix)-margins-\(side)-\(layout.rawValue).png", to: folder)
      }
    }
    panel.showSide(.library)
    await panel.library.setLayout(.grid)
    if let first = panel.library.items.first?.id {
      panel.library.letterJump.top = first
      panel.library.hovered = first
      await write(window, "\(prefix)-margins-first-row.png", to: folder)
      panel.library.hovered = nil
    }
    await panel.library.setSort(.recent)
    await panel.library.setLayout(saved)
  }

  /// Scrolls the tallest scroll view, the books', by `points`: between rows, where a jump to a
  /// book never lands.
  private static func scrollBooks(in window: NSWindow, by points: CGFloat) {
    func scrollViews(in view: NSView) -> [NSScrollView] {
      if let scroll = view as? NSScrollView { return [scroll] }
      return view.subviews.flatMap(scrollViews)
    }
    guard let root = window.contentView,
      let scroll = scrollViews(in: root).max(by: { $0.frame.height < $1.frame.height })
    else { return }
    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + points))
    scroll.reflectScrolledClipView(clip)
  }

  /// Selected and lifted covers in the grid's outer columns and its top and bottom rows.
  private static func renderGridEdges(_ panel: PanelModel, window: NSWindow, to folder: URL) async {
    let ids = panel.library.items.map(\.id)
    guard ids.count > 6 else { return }
    for (name, top, selected, hovered) in [
      ("library-grid-edges-top", ids[0], [ids[0], ids[2], ids[3]], ids[2]),
      ("library-grid-edges-bottom", ids[ids.count - 1], Array(ids.suffix(3)), ids[ids.count - 3]),
    ] {
      panel.library.letterJump.top = top
      select(selected.map(\.rawValue), in: panel)
      panel.library.hovered = hovered
      await write(window, "\(name).png", to: folder)
    }
    await panel.library.setLayout(.shelf)
    await panel.library.setSort(.recent)
    await panel.library.setSort(.title)
    if let first = panel.library.recentItems.first?.id {
      select([first.rawValue], in: panel)
      panel.library.hovered = first
      await write(window, "library-shelf-edges.png", to: folder)
    }
    await panel.library.setLayout(.grid)
    panel.library.hovered = nil
    _ = panel.library.clearSelection()
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

  /// Puts the pointer over a point of the card, measured from its top left, or takes it away.
  private static func hover(_ panel: PanelModel, at point: CGPoint?) {
    let margins = panel.windowMargins
    panel.pointer.location = point.map {
      CGPoint(x: margins.leading + $0.x, y: margins.top + $0.y)
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
