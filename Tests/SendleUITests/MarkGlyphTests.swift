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

  @Test(arguments: [
    (CGSize(width: 15, height: 17), CGSize(width: 6, height: 8)),
    (CGSize(width: 17, height: 15), CGSize(width: 8, height: 6)),
    (CGSize(width: 15, height: 15), CGSize(width: 8, height: 8)),
    (CGSize(width: 11, height: 15), CGSize(width: 6, height: 8)),
  ])
  func aSymbolNearlySquareStaysTallOrWide(natural: CGSize, box: CGSize) {
    #expect(MarkGlyph.size(natural: natural, within: 8) == box)
  }

  @Test func anUnknownSymbolFillsTheBox() {
    #expect(MarkGlyph.size(of: "no.such.symbol", within: 10) == CGSize(width: 10, height: 10))
  }
}
