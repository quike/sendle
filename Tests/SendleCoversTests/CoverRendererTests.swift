import Foundation
import SendleCovers
import SendleTestSupport
import Testing

struct CoverRendererTests {
  let folder: URL

  init() throws {
    folder = try makeTemporaryDirectory()
  }

  @Test func shrinksAnImageToFitKeepingItsShape() throws {
    let image = folder.appending(path: "cover.png")
    try ImageFixtures.png(width: 400, height: 600).write(to: image)

    let png = try #require(CoverRenderer.png(fromImageAt: image, maxPixel: 150))

    #expect(ImageFixtures.size(of: png)?.width == 100)
    #expect(ImageFixtures.size(of: png)?.height == 150)
    #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
  }

  @Test func rendersAPDFsFirstPageAtTheRequestedSize() throws {
    let pdf = folder.appending(path: "manual.pdf")
    try ImageFixtures.writePDF(width: 200, height: 300, to: pdf)

    let png = try #require(CoverRenderer.png(fromPDFAt: pdf, maxPixel: 600))

    #expect(ImageFixtures.size(of: png)?.width == 400)
    #expect(ImageFixtures.size(of: png)?.height == 600)
    #expect(ImageFixtures.centreColour(of: png) == [0, 0, 0])
  }

  @Test func returnsNilForFilesItCannotRead() throws {
    let junk = folder.appending(path: "junk.jpg")
    try Data("not an image".utf8).write(to: junk)

    #expect(CoverRenderer.png(fromImageAt: junk, maxPixel: 100) == nil)
    #expect(CoverRenderer.png(fromPDFAt: junk, maxPixel: 100) == nil)
    #expect(
      CoverRenderer.png(fromImageAt: folder.appending(path: "gone.png"), maxPixel: 100) == nil)
  }
}
