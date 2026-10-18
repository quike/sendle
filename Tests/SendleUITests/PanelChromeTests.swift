import CoreGraphics
import SendleUI
import SwiftUI
import Testing

@MainActor
struct PanelChromeTests {
  /// The alpha of every pixel on the outer edge of the rendered window.
  func edgeAlphas(scale: CGFloat) throws -> [UInt8] {
    let renderer = ImageRenderer(content: PanelChrome(arrowOffset: 0) { Color.clear })
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

  @Test func theWindowIsTheSizeOfTheCardAndItsMargins() throws {
    let renderer = ImageRenderer(content: PanelChrome(arrowOffset: 0) { Color.clear })
    let image = try #require(renderer.cgImage)

    #expect(CGFloat(image.width) == PanelView.windowSize.width)
    #expect(CGFloat(image.height) == PanelView.windowSize.height)
  }

  /// A shadow cut off by the window's edge showed as a dark square behind the rounded corners.
  @Test(arguments: [1, 2] as [CGFloat])
  func theShadowFadesOutInsideTheWindow(scale: CGFloat) throws {
    #expect(try edgeAlphas(scale: scale).max() == 0)
  }
}
