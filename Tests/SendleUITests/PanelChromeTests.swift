import CoreGraphics
import SendleUI
import SwiftUI
import Testing

@MainActor
struct PanelChromeTests {
  /// The whole card, and one shrunk to fit a short screen.
  nonisolated static let cards = [Theme.cardSize, CGSize(width: Theme.cardSize.width, height: 480)]

  /// The alpha of every pixel on the outer edge of the rendered window.
  func edgeAlphas(card: CGSize, scale: CGFloat) throws -> [UInt8] {
    try edgeAlphas(of: PanelChrome(arrowOffset: 0, size: card) { Color.clear }, scale: scale)
  }

  func edgeAlphas(of view: some View, scale: CGFloat) throws -> [UInt8] {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    let image = try #require(renderer.cgImage)
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
    let rows = (0..<width).flatMap { [alpha($0, 0), alpha($0, height - 1)] }
    let columns = (0..<height).flatMap { [alpha(0, $0), alpha(width - 1, $0)] }
    return rows + columns
  }

  @Test(arguments: cards)
  func theWindowIsTheSizeOfTheCardAndItsMargins(card: CGSize) throws {
    let renderer = ImageRenderer(content: PanelChrome(arrowOffset: 0, size: card) { Color.clear })
    let image = try #require(renderer.cgImage)
    let size = PanelView.windowSize(margins: PanelView.margins, card: card)

    #expect(CGFloat(image.width) == size.width)
    #expect(CGFloat(image.height) == size.height)
  }

  @Test func theWholeCardIsTheDefault() {
    #expect(
      PanelView.windowSize == PanelView.windowSize(margins: PanelView.margins, card: Theme.cardSize)
    )
  }

  /// A shadow cut off by the window's edge showed as a dark square behind the rounded corners.
  @Test(arguments: cards, [1, 2] as [CGFloat])
  func theShadowFadesOutInsideTheWindow(card: CGSize, scale: CGFloat) throws {
    #expect(try edgeAlphas(card: card, scale: scale).max() == 0)
  }

  /// The panel with both floating cards, the A–Z card as tall as books that reach down to the
  /// card's bottom padding.
  func floatingWindow(side: RailSide, card size: CGSize = Theme.cardSize) -> some View {
    let margins = FloatingControls.margins(side: side)
    let card = CGRect(origin: CGPoint(x: margins.leading, y: margins.top), size: size)
    let books = CGRect(
      x: card.minX + 14, y: card.minY + 120, width: card.width - 28, height: card.height - 134)
    let send = FloatingControls.sendFrame(card: card)
    let rail = FloatingControls.railFrame(card: card, books: books, side: side, height: nil)
    return PanelChrome(arrowOffset: 0, margins: margins, size: size) { Color.clear }
      .overlay(alignment: .topLeading) {
        FloatingCard(size: send.size, cornerRadius: FloatingControls.sendRadius) { Color.clear }
          .offset(x: send.minX, y: send.minY)
      }
      .overlay(alignment: .topLeading) {
        FloatingCard(size: rail.size, cornerRadius: FloatingControls.railWidth / 2) {
          Color.clear
        }
        .offset(x: rail.minX, y: rail.minY)
      }
  }

  @Test(arguments: [RailSide.leading, .trailing])
  func theWindowGrowsByTheFloatingCardsAlone(side: RailSide) throws {
    let renderer = ImageRenderer(content: floatingWindow(side: side))
    let image = try #require(renderer.cgImage)
    let size = PanelView.windowSize(margins: FloatingControls.margins(side: side))

    #expect(CGFloat(image.width) == size.width)
    #expect(CGFloat(image.height) == size.height)
  }

  @Test(arguments: [RailSide.leading, .trailing], [1, 2] as [CGFloat])
  func theFloatingCardsShadowsFadeOutInsideTheWindow(side: RailSide, scale: CGFloat) throws {
    #expect(try edgeAlphas(of: floatingWindow(side: side), scale: scale).max() == 0)
  }

  @Test(arguments: [RailSide.leading, .trailing])
  func aShrunkCardsFloatingCardsShadowsFadeOutInsideTheWindow(side: RailSide) throws {
    let card = Self.cards[1]
    #expect(try edgeAlphas(of: floatingWindow(side: side, card: card), scale: 2).max() == 0)
    let image = try #require(ImageRenderer(content: floatingWindow(side: side, card: card)).cgImage)
    let size = PanelView.windowSize(margins: FloatingControls.margins(side: side), card: card)
    #expect(CGFloat(image.height) == size.height)
  }
}
