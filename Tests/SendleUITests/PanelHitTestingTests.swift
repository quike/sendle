import AppKit
import SendleDomain
import SendleTestSupport
import SendleUI
import SwiftUI
import Testing

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PanelHitTestingTests {
  /// The floating send card sits under the panel's card, so nothing of it may take the clicks and
  /// scrolls meant for the books above it.
  @Test(arguments: [LibraryLayout.grid, .list, .shelf])
  func theBooksAboveTheSendCardTakeClicksAndScrolls(layout: LibraryLayout) async throws {
    let harness = PanelHarness()
    harness.library.result = .success(
      (0..<40).map { .fixture(id: "b\($0)", title: "Book \($0)", author: "Writer \($0)") })
    var saved = AppSettings(email: .fixture)
    saved.layout = layout
    saved.controls = .floating
    let (panel, _) = harness.makePanel(saved)
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()
    #expect(panel.showsSendCard)

    let (window, host) = try await show(panel)
    defer { window.orderOut(nil) }

    let margins = panel.windowMargins
    let x = margins.leading + panel.cardSize.width / 2 - 60
    for height in stride(from: 30.0, through: 210, by: 20) {
      let hit = host.superview?.hitTest(NSPoint(x: x, y: margins.bottom + height))
      #expect(
        hit is NSScrollView || hit?.enclosingScrollView != nil,
        "\(Int(height)) pt above the card's bottom, a click reaches \(hit.map { "\(type(of: $0))" } ?? "nothing")"
      )
    }
  }

  @Test func aClickOnAKindleBookOpensItsDetails() async throws {
    let harness = PanelHarness()
    let book = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.pdf", source: .sendle, asin: "SNMOBYDICK",
      asinFollowsFileName: true)
    let (panel, _, _) = await harness.pluggedInPanel(listing: [book])
    panel.showSide(.kindle)
    let (window, _) = try await show(panel)
    defer { window.orderOut(nil) }

    try click(at: firstCoverCentre(of: panel), in: window)

    #expect(await eventually { panel.kindleDetails?.item.book.id == book.id })
  }

  @Test func aClickOnTheEditCircleOpensDetailsAndSelectsNothing() async throws {
    let (panel, _) = PanelHarness().makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    let first = try #require(panel.library.items.first?.id)
    let (window, host) = try await show(panel)
    defer { window.orderOut(nil) }
    panel.library.hovered = first
    try await layOut(window, host)

    let cover = firstCoverFrame(of: panel)
    let send = NSPoint(x: cover.maxX - (6 + 14), y: cover.minY + 6 + 14)
    try click(at: NSPoint(x: send.x, y: send.y + 34), in: window)

    #expect(await eventually { panel.bookDetails?.book.id == first })
    #expect(panel.library.selection.ids.isEmpty)
    #expect(panel.queue.isEmpty)
  }

  /// `panel` in a borderless window of its size, laid out and drawn.
  private func show(_ panel: PanelModel) async throws -> (NSWindow, NSHostingView<PanelView>) {
    let size = PanelView.windowSize(margins: panel.windowMargins, card: panel.cardSize)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
      defer: false)
    let host = NSHostingView(rootView: PanelView(panel: panel))
    host.sizingOptions = []
    window.contentView = host
    window.orderFrontRegardless()
    try await layOut(window, host)
    return (window, host)
  }

  private func layOut(_ window: NSWindow, _ host: NSHostingView<PanelView>) async throws {
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  private func firstCoverCentre(of panel: PanelModel) -> NSPoint {
    let frame = firstCoverFrame(of: panel)
    return NSPoint(x: frame.midX, y: frame.midY)
  }

  /// The grid's first cover, unlifted, in the window's coordinates, which start at its bottom.
  private func firstCoverFrame(of panel: PanelModel) -> NSRect {
    let margins = panel.windowMargins
    let padding = BooksArea.screenPadding
    let columns = CGFloat(BookGridMetrics.columns)
    let grid = panel.cardSize.width - 2 * (padding + BooksArea.gridInset)
    let column = (grid - (columns - 1) * BookGridMetrics.columnSpacing) / columns
    let top =
      margins.top + padding
      + LibraryControls.height(withKindle: panel.library.isKindlePluggedIn)
      + BooksArea.controlsGap + BooksArea.insets.top + BooksArea.liftRoom
    let height = PanelView.windowSize(margins: margins, card: panel.cardSize).height
    return NSRect(
      x: margins.leading + padding + BooksArea.gridInset, y: height - top - column * 3 / 2,
      width: column, height: column * 3 / 2)
  }

  private func click(at point: NSPoint, in window: NSWindow) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
      window.sendEvent(event)
    }
  }
}
