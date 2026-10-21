import CoreGraphics
import SendleUI
import Testing

@MainActor
struct MarkGlyphTests {
  @Test(arguments: [
    "ipad", "questionmark", "checkmark", "cable.connector", "envelope.fill", "icloud.fill",
    "pencil.line",
  ])
  func aMarksGlyphHasEvenSidesSoItSitsOnWholePixels(symbol: String) {
    let size = MarkGlyph.size(of: symbol, within: 8)
    #expect(size.width.truncatingRemainder(dividingBy: 2) == 0)
    #expect(size.height.truncatingRemainder(dividingBy: 2) == 0)
    #expect(max(size.width, size.height) == 8)
  }

  @Test func aGlyphKeepsItsSymbolsShape() {
    let tall = MarkGlyph.size(of: "ipad", within: 8)
    let wide = MarkGlyph.size(of: "envelope.fill", within: 8)
    #expect(tall.height > tall.width)
    #expect(wide.width > wide.height)
  }

  @Test func anUnknownSymbolFillsTheBox() {
    #expect(MarkGlyph.size(of: "no.such.symbol", within: 10) == CGSize(width: 10, height: 10))
  }
}
