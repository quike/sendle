import CryptoKit
import Foundation

/// What a Kindle's library reads from a KF8 book (AZW3): its ASIN, its type and its cover. The
/// library keys a sideloaded book's cover by ASIN and type (see `KindleThumbnail`).
package struct AZW3Metadata: Equatable, Sendable {
  package var asin: String
  /// "EBOK" for a book, "PDOC" for a personal document.
  package var documentType: String
  package var cover: Data?

  package init(asin: String, documentType: String, cover: Data?) {
    self.asin = asin
    self.documentType = documentType
    self.cover = cover
  }

  /// Nil unless `data` is a Kindle book with an ASIN and a type.
  package init?(_ data: Data) {
    let source = DataBytes(data)
    guard let book = MobiLayout(source),
      let asin = book.range(of: Self.asinEntry).flatMap(source.bytes),
      let type = book.range(of: Self.typeEntry).flatMap(source.bytes)
    else { return nil }
    self.asin = String(decoding: asin, as: UTF8.self)
    documentType = String(decoding: type, as: UTF8.self)
    cover = book.cover.flatMap(source.bytes).map { Data($0) }
  }

  /// `data` with `asin` in place of the book's own, which must be as long, so nothing else moves.
  package static func replacingASIN(in data: Data, with asin: String) -> Data? {
    let replacement = Array(asin.utf8)
    guard let range = MobiLayout(DataBytes(data))?.range(of: asinEntry),
      range.count == replacement.count
    else { return nil }
    var file = [UInt8](data)
    file.replaceSubrange(range, with: replacement)
    return Data(file)
  }

  /// Ten characters, like Amazon's ASINs, but starting "SN", which no Amazon product does. The
  /// same name always gives the same ASIN, so a book sent again keeps its cover.
  package static func asin(for name: String) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    let digest = SHA256.hash(data: Data(name.utf8))
    return "SN" + digest.prefix(8).map { String(alphabet[Int($0) % alphabet.count]) }.joined()
  }

  private static let asinEntry: UInt32 = 113
  private static let typeEntry: UInt32 = 501
}
