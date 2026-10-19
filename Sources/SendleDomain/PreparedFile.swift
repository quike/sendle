import Foundation

/// Formats Sendle can hand to a delivery channel.
public enum FileFormat: String, Sendable, Codable, CaseIterable {
  case epub
  case pdf
  case azw3
  case txt

  public var fileExtension: String { rawValue }

  public var mimeType: String {
    switch self {
    case .epub: "application/epub+zip"
    case .pdf: "application/pdf"
    case .azw3: "application/vnd.amazon.ebook"
    case .txt: "text/plain; charset=utf-8"
    }
  }
}

/// Repairs applied to an EPUB because Amazon rejects or garbles books without them.
public enum EPUBFix: String, Sendable, Codable, CaseIterable {
  case addedXMLDeclaration
  case addedLanguage
  case removedBodyIDLinks
  case removedEmptyImages
}

/// A file ready to deliver. Channels read its size from disk.
public struct PreparedFile: Sendable, Hashable {
  public let url: URL
  public let format: FileFormat
  public let fixes: [EPUBFix]
  public let edition: Edition?
  /// What the ASIN of a delivered AZW3 derives from, when it isn't the delivered name.
  public let asinSeed: String?

  public init(
    url: URL, format: FileFormat, fixes: [EPUBFix] = [], edition: Edition? = nil,
    asinSeed: String? = nil
  ) {
    self.url = url
    self.format = format
    self.fixes = fixes
    self.edition = edition
    self.asinSeed = asinSeed
  }
}
