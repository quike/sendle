import Darwin
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
  public func cover(for book: Book, maxPixel: Int) async -> Cover {
    guard maxPixel > 0, book.availability == .ready || book.availability == .protected
    else { return .none }
    return withoutDownloads { cachedCover(for: book, maxPixel: maxPixel) } ?? .unreadable
  }

  /// A file that has gone, or gone back to iCloud, since the library was read may come back.
  private func cachedCover(for book: Book, maxPixel: Int) -> Cover {
    guard let modified = Self.localModificationTime(of: book.fileURL) else { return .unreadable }
    let cached = cacheDirectory.appending(
      path: "\(Self.fileName(for: book.id))-\(modified)-\(maxPixel).png")
    if let data = try? Data(contentsOf: cached) { return .image(data) }
    guard let png = Self.render(book, maxPixel: maxPixel) else { return .none }
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try? png.write(to: cached, options: .atomic)
    return .image(png)
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

  /// Seconds since 1970, read fresh with `stat` (`URL` resource values are cached per instance).
  /// Nil when the file is missing or is an iCloud placeholder.
  private static func localModificationTime(of url: URL) -> Int? {
    var info = stat()
    guard stat(url.path(percentEncoded: false), &info) == 0,
      info.st_flags & UInt32(SF_DATALESS) == 0
    else { return nil }
    return Int(info.st_mtimespec.tv_sec)
  }

  /// Book IDs are Books' own strings; percent-encoding keeps them distinct and path-safe.
  private static func fileName(for id: BookID) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return id.rawValue.addingPercentEncoding(withAllowedCharacters: safe) ?? "book"
  }
}
