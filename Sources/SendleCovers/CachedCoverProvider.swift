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

  /// The chosen cover is Sendle's own file, so it shows whatever the book's availability. The book
  /// itself is only read when it is on this Mac, so a cover can't trigger an iCloud download.
  public func cover(for book: Book, maxPixel: Int) async -> Cover {
    guard maxPixel > 0 else { return .none }
    if let edited = book.edits.cover,
      let png = editedCover(at: edited, for: book, maxPixel: maxPixel)
    {
      return .image(png)
    }
    guard book.availability == .ready || book.availability == .protected else { return .none }
    return withoutDownloads { cachedCover(for: book, maxPixel: maxPixel) } ?? .unreadable
  }

  /// The image's file name changes with its content, so it stands in for the file's date.
  private func editedCover(at image: URL, for book: Book, maxPixel: Int) -> Data? {
    let stem = image.deletingPathExtension().lastPathComponent
    return cached("\(Self.fileName(for: book.id))-edit-\(stem)-\(maxPixel).png") {
      CoverRenderer.png(fromImageAt: image, maxPixel: maxPixel)
    }
  }

  /// A file that has gone, or gone back to iCloud, since the library was read may come back.
  private func cachedCover(for book: Book, maxPixel: Int) -> Cover {
    guard let modified = Self.localModificationTime(of: book.fileURL) else { return .unreadable }
    let name = "\(Self.fileName(for: book.id))-\(modified)-\(maxPixel).png"
    return cached(name) { Self.render(book, maxPixel: maxPixel) }.map(Cover.image) ?? .none
  }

  private func cached(_ name: String, render: () -> Data?) -> Data? {
    let file = cacheDirectory.appending(path: name)
    if let data = try? Data(contentsOf: file) { return data }
    guard let png = render() else { return nil }
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try? png.write(to: file, options: .atomic)
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
