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

  @Test func theRecentStripStaysPutWhileTheListScrolls() async throws {
    let harness = PanelHarness()
    harness.library.result = .success(
      (0..<40).map { .fixture(id: "b\($0)", title: "Book \($0)", author: "Writer \($0)") })
    var saved = AppSettings(email: .fixture)
    saved.layout = .shelf
    saved.sort = .title
    let (panel, _) = harness.makePanel(saved)
    await panel.launch()
    await panel.panelDidOpen()
    let (window, host) = try await show(panel)
    defer { window.orderOut(nil) }
    panel.library.letterJump.top = panel.library.items.last?.id
    for _ in 0..<2 { try await layOut(window, host) }

    let scrolled = try #require(listScrollOffset(in: host))
    #expect(scrolled > 0)

    try click(at: firstStripCoverCentre(of: panel), in: window)

    let recent = try #require(panel.library.recentItems.first?.id)
    #expect(await eventually { panel.library.selection.contains(recent) })
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
    let (panel, window, first) = try await hoveringFirstBook()
    defer { window.orderOut(nil) }

    let send = coverSendCentre(of: panel)
    try click(at: NSPoint(x: send.x, y: send.y + 34), in: window)

    #expect(await eventually { panel.bookDetails?.book.id == first })
    #expect(panel.library.selection.ids.isEmpty)
    #expect(panel.queue.isEmpty)
  }

  @Test func aClickOnARowsEditCircleOpensDetailsAndSelectsNothing() async throws {
    let (panel, window, first) = try await hoveringFirstBook(in: .list)
    defer { window.orderOut(nil) }

    let send = rowSendCentre(of: panel)
    try click(at: NSPoint(x: send.x - 34, y: send.y), in: window)

    #expect(await eventually { panel.bookDetails?.book.id == first })
    #expect(panel.library.selection.ids.isEmpty)
    #expect(panel.queue.isEmpty)
  }

  @Test func aCoverThatCantBeSentHasTheEditCircleInTheSendCirclesPlace() async throws {
    let (panel, window, first) = try await hoveringFirstBook(
      of: [.fixture(id: "a", availability: .inCloudOnly)])
    defer { window.orderOut(nil) }

    try click(at: coverSendCentre(of: panel), in: window)

    #expect(await eventually { panel.bookDetails?.book.id == first })
  }

  /// A store purchase that can be sent isn't edited, so where the edit circle would sit the
  /// cover takes the click and selects it.
  @Test func aBookWhoseDetailsCantBeEditedHasNoEditCircle() async throws {
    let (panel, window, first) = try await hoveringFirstBook(
      of: [.fixture(id: "a", isStorePurchase: true)])
    defer { window.orderOut(nil) }

    let send = coverSendCentre(of: panel)
    try click(at: NSPoint(x: send.x, y: send.y + 34), in: window)

    #expect(await eventually { panel.library.selection.ids == [first] })
    #expect(panel.bookDetails == nil)
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

  /// A shown panel of `books` in `layout`, once the pointer has rested on its first book long
  /// enough for the hover's circles to stop moving.
  private func hoveringFirstBook(of books: [Book]? = nil, in layout: LibraryLayout = .grid)
    async throws -> (PanelModel, NSWindow, BookID)
  {
    let harness = PanelHarness()
    if let books { harness.library.result = .success(books) }
    var saved = AppSettings(email: .fixture)
    saved.layout = layout
    let (panel, _) = harness.makePanel(saved)
    await panel.launch()
    await panel.panelDidOpen()
    let first = try #require(panel.library.items.first?.id)
    let (window, host) = try await show(panel)
    panel.library.hovered = first
    for _ in 0..<2 { try await layOut(window, host) }
    return (panel, window, first)
  }

  /// How far the books' list has scrolled from its rest: the one scroll view that holds more than
  /// it shows, as the strip's scrolls sideways.
  private func listScrollOffset(in view: NSView) -> CGFloat? {
    if let scroll = view as? NSScrollView, let document = scroll.documentView,
      document.frame.height > scroll.frame.height
    {
      return scroll.contentView.bounds.minY + scroll.contentInsets.top
    }
    return view.subviews.lazy.compactMap { listScrollOffset(in: $0) }.first
  }

  private func firstCoverCentre(of panel: PanelModel) -> NSPoint {
    let frame = firstCoverFrame(of: panel)
    return NSPoint(x: frame.midX, y: frame.midY)
  }

  /// The first of Shelf's recent covers, 62 × 93 pt, under the "Recently added" label and the
  /// strip's 6 pt and 8 pt padding.
  private func firstStripCoverCentre(of panel: PanelModel) -> NSPoint {
    let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    let label = (font.ascender - font.descender + font.leading).rounded(.up)
    return NSPoint(
      x: panel.windowMargins.leading + BooksArea.screenPadding + 6 + 62 / 2,
      y: booksTop(of: panel) - label - 8 - 93 / 2)
  }

  /// The send circle's place on the first cover, 6 pt in from its bottom-right corner.
  private func coverSendCentre(of panel: PanelModel) -> NSPoint {
    let cover = firstCoverFrame(of: panel)
    return NSPoint(x: cover.maxX - (6 + 14), y: cover.minY + 6 + 14)
  }

  /// The send circle at the end of the first row, inside the row's 7 pt padding.
  private func rowSendCentre(of panel: PanelModel) -> NSPoint {
    let padding = BooksArea.screenPadding
    let rowHeight: CGFloat = 7 + 50 + 7
    return NSPoint(
      x: panel.windowMargins.leading + panel.cardSize.width - padding - 7 - 14,
      y: booksTop(of: panel) - rowHeight / 2)
  }

  /// The grid's first cover, unlifted.
  private func firstCoverFrame(of panel: PanelModel) -> NSRect {
    let padding = BooksArea.screenPadding
    let columns = CGFloat(BookGridMetrics.columns)
    let grid = panel.cardSize.width - 2 * (padding + BooksArea.gridInset)
    let column = (grid - (columns - 1) * BookGridMetrics.columnSpacing) / columns
    return NSRect(
      x: panel.windowMargins.leading + padding + BooksArea.gridInset,
      y: booksTop(of: panel) - column * 3 / 2, width: column, height: column * 3 / 2)
  }

  /// The top of the first book, in the window's coordinates, which start at its bottom.
  private func booksTop(of panel: PanelModel) -> CGFloat {
    let margins = panel.windowMargins
    let top =
      margins.top + BooksArea.screenPadding
      + LibraryControls.height(withKindle: panel.library.isKindlePluggedIn)
      + BooksArea.controlsGap + BooksArea.insets.top + BooksArea.liftRoom
    return PanelView.windowSize(margins: margins, card: panel.cardSize).height - top
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
