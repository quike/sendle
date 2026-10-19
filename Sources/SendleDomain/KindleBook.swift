import Foundation

/// A book's place on a Kindle: its path under `documents/`, `/`-separated.
public struct KindleBookID: Hashable, Sendable, Codable {
  public let relativePath: String

  public init(relativePath: String) {
    self.relativePath = relativePath
  }
}

/// Where a book on a Kindle came from, as far as its file tells.
public enum KindleBookSource: String, Hashable, Sendable, Codable, CaseIterable {
  case sendle
  case calibre
  case amazon
  case email
  case byHand

  public static func detect(
    relativePath: String, asin: String?, calibreLibrary: Bool
  ) -> KindleBookSource {
    if let asin, asin.hasPrefix("SN"), asin.count == 10 { return .sendle }
    let parsed = KindleFileName.parse(relativePath)
    let inDownloads = relativePath.hasPrefix("Downloads/Items01/")
    if inDownloads, parsed.amazonID?.count == 32 { return .email }
    if let asin, asin.count == 36, UUID(uuidString: asin) != nil { return .calibre }
    if calibreLibrary, !inDownloads, relativePath.contains("/") { return .calibre }
    if let asin, isAmazonASIN(asin) { return .amazon }
    if inDownloads, parsed.amazonID?.count == 10 { return .amazon }
    return .byHand
  }

  private static func isAmazonASIN(_ asin: String) -> Bool {
    asin.count == 10 && asin.hasPrefix("B0")
      && asin.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
  }
}

public struct KindleBook: Identifiable, Hashable, Sendable, Codable {
  public let id: KindleBookID
  public let title: String
  public let authors: [String]
  public let source: KindleBookSource
  public let asin: String?
  public let documentType: String?
  public let isbn: String?
  public let publisher: String?
  /// True when the ASIN is the one Sendle derives from the file name, not an edition key.
  public let asinFollowsFileName: Bool
  public let isProtected: Bool
  public let byteCount: Int64
  public let modified: Date

  public init(
    id: KindleBookID,
    title: String,
    authors: [String],
    source: KindleBookSource,
    asin: String? = nil,
    documentType: String? = nil,
    isbn: String? = nil,
    publisher: String? = nil,
    asinFollowsFileName: Bool = false,
    isProtected: Bool = false,
    byteCount: Int64,
    modified: Date
  ) {
    self.id = id
    self.title = title
    self.authors = authors
    self.source = source
    self.asin = asin
    self.documentType = documentType
    self.isbn = isbn
    self.publisher = publisher
    self.asinFollowsFileName = asinFollowsFileName
    self.isProtected = isProtected
    self.byteCount = byteCount
    self.modified = modified
  }

  public func withSource(_ source: KindleBookSource) -> KindleBook {
    KindleBook(
      id: id, title: title, authors: authors, source: source, asin: asin,
      documentType: documentType, isbn: isbn, publisher: publisher,
      asinFollowsFileName: asinFollowsFileName, isProtected: isProtected, byteCount: byteCount,
      modified: modified)
  }

  /// The lowercased extension.
  public var format: String {
    let name = fileName
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    return name[name.index(after: dot)...].lowercased()
  }

  public var fileName: String {
    id.relativePath.split(separator: "/").last.map(String.init) ?? id.relativePath
  }

  public var stem: String {
    KindleFileName.stem(of: fileName)
  }

  public func url(on volume: KindleVolume) -> URL {
    volume.mountURL.appending(path: "documents").appending(path: id.relativePath)
  }
}

public struct KindleListing: Hashable, Sendable {
  public let books: [KindleBook]
  public let freeBytes: Int64?

  public init(books: [KindleBook], freeBytes: Int64?) {
    self.books = books
    self.freeBytes = freeBytes
  }
}

public enum KindleListingError: Error, Hashable, Sendable {
  case deviceDisconnected
  case cancelled
  case unreadable(String)
}
