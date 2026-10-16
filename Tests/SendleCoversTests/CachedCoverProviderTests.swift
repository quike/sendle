import Foundation
import SendleCovers
import SendleDomain
import SendleTestSupport
import Testing

struct CachedCoverProviderTests {
  let folder: URL
  let cache: URL
  let provider: CachedCoverProvider
  let epub: URL

  init() throws {
    folder = try makeTemporaryDirectory()
    cache = folder.appending(path: "covers", directoryHint: .isDirectory)
    provider = CachedCoverProvider(cacheDirectory: cache)
    epub = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
  }

  @Test func rendersAnEPUBsCoverImage() async throws {
    try writeEPUB(cover: try ImageFixtures.png(width: 300, height: 450))

    let png = try #require(await provider.cover(for: book(), maxPixel: 120))

    #expect(ImageFixtures.size(of: png)?.width == 80)
    #expect(ImageFixtures.size(of: png)?.height == 120)
  }

  @Test func rendersAPDFsFirstPage() async throws {
    let pdf = folder.appending(path: "Manual.pdf")
    try ImageFixtures.writePDF(width: 300, height: 200, to: pdf)

    let png = try #require(await provider.cover(for: book(format: .pdf, at: pdf), maxPixel: 90))

    #expect(ImageFixtures.size(of: png)?.width == 90)
    #expect(ImageFixtures.size(of: png)?.height == 60)
  }

  @Test func servesLaterRequestsFromTheCache() async throws {
    try writeEPUB(cover: try ImageFixtures.png(width: 300, height: 450))
    _ = await provider.cover(for: book(), maxPixel: 120)
    let cached = try #require(try cacheFiles().first)
    try Data("cached".utf8).write(to: cache.appending(path: cached))

    #expect(await provider.cover(for: book(), maxPixel: 120) == Data("cached".utf8))
    #expect(cached.hasPrefix("book%2F1-"))
    #expect(cached.hasSuffix("-120.png"))
  }

  @Test func keepsOneCoverPerSize() async throws {
    try writeEPUB(cover: try ImageFixtures.png(width: 300, height: 450))

    let small = try #require(await provider.cover(for: book(), maxPixel: 60))
    let large = try #require(await provider.cover(for: book(), maxPixel: 300))

    #expect(ImageFixtures.size(of: small)?.height == 60)
    #expect(ImageFixtures.size(of: large)?.height == 300)
    #expect(try cacheFiles().count == 2)
  }

  @Test func rendersAgainWhenTheBookChanges() async throws {
    try writeEPUB(cover: try ImageFixtures.png(width: 300, height: 450))
    _ = await provider.cover(for: book(), maxPixel: 120)
    let cached = try #require(try cacheFiles().first)
    try Data("stale".utf8).write(to: cache.appending(path: cached))

    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 3_600)],
      ofItemAtPath: epub.path(percentEncoded: false))

    let fresh = try #require(await provider.cover(for: book(), maxPixel: 120))
    #expect(ImageFixtures.size(of: fresh)?.height == 120)
  }

  @Test(arguments: [Availability.inCloudOnly, .missing])
  func neverTouchesABookThatIsNotOnThisMac(availability: Availability) async throws {
    try writeEPUB(cover: try ImageFixtures.png(width: 300, height: 450))

    #expect(await provider.cover(for: book(availability: availability), maxPixel: 120) == nil)
    #expect(!FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
  }

  @Test func returnsNilWhenThereIsNoUsableCover() async throws {
    try EPUBFixture.book().write(to: epub)
    #expect(await provider.cover(for: book(), maxPixel: 120) == nil)

    try writeEPUB(cover: Data("not an image".utf8))
    #expect(await provider.cover(for: book(), maxPixel: 120) == nil)
    #expect(await provider.cover(for: book(), maxPixel: 0) == nil)
    #expect(!FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
  }

  private func writeEPUB(cover: Data) throws {
    var fixture = EPUBFixture.book(
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="cover.png" media-type="image/png" properties="cover-image"/>"#)
    fixture.files["OEBPS/cover.png"] = cover
    try fixture.write(to: epub)
  }

  private func book(
    format: BookFormat = .epub, at url: URL? = nil, availability: Availability = .ready
  ) -> Book {
    .fixture(id: "book/1", format: format, fileURL: url ?? epub, availability: availability)
  }

  private func cacheFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: cache.path(percentEncoded: false))
  }
}
