import Foundation
import PDFKit
import SendleDomain

/// Reads what a Kindle book's file says about it, from its headers or its name, never the whole file.
package enum KindleBookReader {
  package static let formats: Set<String> = [
    "azw", "mobi", "azw3", "prc", "azw1", "tpz", "azw4", "kfx", "pobi", "pdf", "txt",
  ]
  private static let mobiFormats: Set<String> = [
    "azw", "mobi", "azw3", "prc", "azw1", "tpz", "azw4", "pobi",
  ]
  private static let drmionMagic: [UInt8] = [0xEA, 0x44, 0x52, 0x4D, 0x49, 0x4F, 0x4E, 0xEE]

  package struct Reading {
    package let book: KindleBook
    /// False when the file's headers couldn't be read, so the book is listed by its file name.
    package let readHeaders: Bool
  }

  package static func read(
    _ file: URL, relativePath: String, size: Int64, modified: Date, calibreLibrary: Bool
  ) -> Reading {
    let parsed = KindleFileName.parse(relativePath)
    let format = file.pathExtension.lowercased()
    var details = Details(title: parsed.title, authors: parsed.authors)
    if mobiFormats.contains(format) {
      details = mobiDetails(of: file, filling: details)
    } else if format == "pdf" {
      details = pdfDetails(of: file, filling: details)
    } else if format == "kfx" {
      details = kfxDetails(of: file, parsed: parsed, filling: details)
    }
    let asinFollowsFileName =
      details.asin != nil
      && details.asin == AZW3Metadata.asin(for: file.deletingPathExtension().lastPathComponent)
    let book = KindleBook(
      id: KindleBookID(relativePath: relativePath),
      title: details.title,
      authors: details.authors,
      source: KindleBookSource.detect(
        relativePath: relativePath, asin: details.asin, calibreLibrary: calibreLibrary),
      asin: details.asin,
      documentType: details.documentType,
      isbn: details.isbn,
      publisher: details.publisher,
      language: details.language,
      year: details.year,
      asinFollowsFileName: asinFollowsFileName,
      isProtected: details.isProtected,
      byteCount: size,
      modified: modified)
    return Reading(book: book, readHeaders: details.readHeaders)
  }

  private struct Details {
    var title: String
    var authors: [String]
    var asin: String?
    var documentType: String?
    var isbn: String?
    var publisher: String?
    var language: String?
    var year: String?
    var isProtected = false
    var readHeaders = true
  }

  private static func mobiDetails(of file: URL, filling details: Details) -> Details {
    guard let bytes = FileBytes(url: file), let metadata = MobiMetadata(bytes) else {
      var result = details
      result.readHeaders = false
      return result
    }
    var result = details
    result.title = metadata.title ?? details.title
    if !metadata.authors.isEmpty { result.authors = metadata.authors }
    result.asin = metadata.asin
    result.documentType = metadata.documentType
    result.isbn = metadata.isbn
    result.publisher = metadata.publisher
    result.language = metadata.language
    result.year = year(metadata.published)
    result.isProtected = metadata.isEncrypted
    return result
  }

  private static func year(_ published: String?) -> String? {
    guard let year = published?.prefix(4), year.count == 4,
      year.allSatisfy({ $0.isASCII && $0.isNumber })
    else { return nil }
    return String(year)
  }

  private static func pdfDetails(of file: URL, filling details: Details) -> Details {
    guard let document = PDFDocument(url: file) else {
      var result = details
      result.readHeaders = false
      return result
    }
    var result = details
    let attributes = document.documentAttributes
    if let title = text(attributes?[PDFDocumentAttribute.titleAttribute]) { result.title = title }
    if let author = text(attributes?[PDFDocumentAttribute.authorAttribute]) {
      result.authors = [author]
    }
    result.isProtected = document.isEncrypted
    return result
  }

  private static func kfxDetails(
    of file: URL, parsed: KindleFileName.Parsed, filling details: Details
  ) -> Details {
    var result = details
    result.asin = parsed.amazonID
    result.documentType = parsed.amazonID.map { $0.count == 32 ? "PDOC" : "EBOK" }
    let voucher = file.deletingPathExtension().appendingPathExtension("sdr")
      .appending(path: "assets").appending(path: "voucher")
    result.isProtected =
      FileManager.default.fileExists(atPath: voucher.path)
      || FileBytes(url: file)?.bytes(0..<drmionMagic.count) == drmionMagic
    return result
  }

  private static func text(_ value: Any?) -> String? {
    (value as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
  }
}
