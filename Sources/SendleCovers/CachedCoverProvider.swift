import Foundation
import SendleDomain
import SendleEPUB

/// Covers rendered once and kept as PNG files, keyed by book, file date and size.
public struct CachedCoverProvider: CoverProvider {
  private let cacheDirectory: URL

  public init(
    cacheDirectory: URL = URL.cachesDirectory.appending(
      path: "Sendle/covers", directoryHint: .isDirectory)
  ) {
    self.cacheDirectory = cacheDirectory
  }

  /// Never reads a book that isn't on this Mac, so a cover can't trigger an iCloud download.
  public func cover(for book: Book, maxPixel: Int) async -> Data? {
    guard maxPixel > 0, book.availability == .ready || book.availability == .protected,
      let modified = Self.modificationTime(of: book.fileURL)
    else { return nil }
    let cached = cacheDirectory.appending(
      path: "\(Self.fileName(for: book.id))-\(modified)-\(maxPixel).png")
    if let data = try? Data(contentsOf: cached) { return data }
    guard let png = Self.render(book, maxPixel: maxPixel) else { return nil }
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try? png.write(to: cached, options: .atomic)
    return png
  }

  private static func render(_ book: Book, maxPixel: Int) -> Data? {
    switch book.format {
    case .pdf:
      CoverRenderer.png(fromPDFAt: book.fileURL, maxPixel: maxPixel)
    case .epub:
      OPFReader.coverImage(inEPUBAt: book.fileURL).flatMap {
        CoverRenderer.png(fromImageAt: $0, maxPixel: maxPixel)
      }
    }
  }

  /// Read from disk each time: `URL` resource values are cached per URL instance.
  private static func modificationTime(of url: URL) -> Int? {
    let attributes = try? FileManager.default.attributesOfItem(
      atPath: url.path(percentEncoded: false))
    return (attributes?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970) }
  }

  /// Book IDs are Books' own strings; percent-encoding keeps them distinct and path-safe.
  private static func fileName(for id: BookID) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return id.rawValue.addingPercentEncoding(withAllowedCharacters: safe) ?? "book"
  }
}
