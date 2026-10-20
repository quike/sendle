import CoreGraphics
import SendleDomain
import SendleTestSupport
import SendleUI
import SwiftUI
import Testing

/// The floating cards as the panel draws them: the A–Z card stands as far beside the card as the
/// send card stands below it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FloatingGapTests {
  let harness = PanelHarness()

  /// The panel with floating controls, sorted by title with a selection, placed for `side`.
  func panel(side: RailSide, style: JumpBarStyle) async -> PanelModel {
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, jumpBar: style, controls: .floating))
    await panel.launch()
    await panel.panelDidOpen()
    await panel.library.setSort(.title)
    panel.library.selectAll()
    panel.library.letterJump.isHovered = true
    panel.railSide = side
    return panel
  }

  /// Whether each pixel of the rendered window is fully opaque, as only the cards are.
  func opaque(_ view: some View) throws -> (width: Int, height: Int, at: (Int, Int) -> Bool) {
    let image = try #require(ImageRenderer(content: view).cgImage)
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, { x, y in pixels[(y * width + x) * 4 + 3] == 255 })
  }

  /// The narrowest empty stretch between two opaque runs on any of `lines`; nil if none has two.
  func narrowestGap(across lines: [[(Int, Int)]], opaque: (Int, Int) -> Bool) -> Int? {
    var narrowest: Int?
    for line in lines {
      var run = 0
      var seenOpaque = false
      for (x, y) in line {
        if opaque(x, y) {
          if seenOpaque, run > 0 { narrowest = min(narrowest ?? run, run) }
          seenOpaque = true
          run = 0
        } else {
          run += 1
        }
      }
    }
    return narrowest
  }

  @Test(arguments: [RailSide.leading, .trailing], [JumpBarStyle.full, .compact])
  func theAZCardStandsAsFarBesideTheCardAsTheSendCardBelowIt(
    side: RailSide, style: JumpBarStyle
  ) async throws {
    let panel = await panel(side: side, style: style)
    #expect(panel.showsSendCard)

    let window = try opaque(PanelView(panel: panel))

    let columns = (0..<window.width).map { x in (0..<window.height).map { (x, $0) } }
    let rows = (0..<window.height).map { y in (0..<window.width).map { ($0, y) } }
    #expect(narrowestGap(across: columns, opaque: window.at) == Int(FloatingControls.gap))
    #expect(narrowestGap(across: rows, opaque: window.at) == Int(FloatingControls.gap))
  }
}
