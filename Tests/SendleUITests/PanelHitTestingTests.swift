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

    let margins = panel.windowMargins
    let size = PanelView.windowSize(margins: margins, card: panel.cardSize)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
      defer: false)
    let host = NSHostingView(rootView: PanelView(panel: panel))
    host.sizingOptions = []
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
    }

    let x = margins.leading + panel.cardSize.width / 2 - 60
    for height in stride(from: 30.0, through: 210, by: 20) {
      let hit = host.superview?.hitTest(NSPoint(x: x, y: margins.bottom + height))
      #expect(
        hit is NSScrollView || hit?.enclosingScrollView != nil,
        "\(Int(height)) pt above the card's bottom, a click reaches \(hit.map { "\(type(of: $0))" } ?? "nothing")"
      )
    }
  }
}
