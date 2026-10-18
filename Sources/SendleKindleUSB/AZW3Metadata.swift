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
    let file = [UInt8](data)
    guard let book = Layout(file), let asin = book.entries[Self.asinEntry],
      let type = book.entries[Self.typeEntry]
    else { return nil }
    self.asin = String(decoding: file[asin], as: UTF8.self)
    documentType = String(decoding: file[type], as: UTF8.self)
    cover = book.cover.map { Data(file[$0]) }
  }

  /// `data` with `asin` in place of the book's own, which must be as long, so nothing else moves.
  package static func replacingASIN(in data: Data, with asin: String) -> Data? {
    var file = [UInt8](data)
    let replacement = Array(asin.utf8)
    guard let range = Layout(file)?.entries[asinEntry], range.count == replacement.count else {
      return nil
    }
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
  private static let coverEntry: UInt32 = 201

  /// Where record 0's EXTH entries and the cover record sit in the file (MobileRead's MOBI page).
  private struct Layout {
    var entries: [UInt32: Range<Int>] = [:]
    var cover: Range<Int>?

    init?(_ file: [UInt8]) {
      guard file.count >= 78, file[60..<68].elementsEqual("BOOKMOBI".utf8),
        let count = file.uint16(at: 76).map(Int.init), count > 0
      else { return nil }
      var starts: [Int] = []
      for index in 0..<count {
        guard let start = file.uint32(at: 78 + 8 * index).map(Int.init), start <= file.count
        else { return nil }
        starts.append(start)
      }
      func record(_ index: Int) -> Range<Int>? {
        guard index < count else { return nil }
        let end = index + 1 < count ? starts[index + 1] : file.count
        return starts[index] <= end ? starts[index]..<end : nil
      }
      guard let header = record(0), file.count >= header.lowerBound + 24,
        file[(header.lowerBound + 16)..<(header.lowerBound + 20)].elementsEqual("MOBI".utf8),
        let mobiLength = file.uint32(at: header.lowerBound + 20).map(Int.init)
      else { return nil }
      var position = header.lowerBound + 16 + mobiLength
      guard position + 12 <= header.upperBound,
        file[position..<(position + 4)].elementsEqual("EXTH".utf8),
        let entryCount = file.uint32(at: position + 8)
      else { return nil }
      position += 12
      for _ in 0..<entryCount {
        guard let kind = file.uint32(at: position),
          let length = file.uint32(at: position + 4).map(Int.init), length >= 8,
          position + length <= header.upperBound
        else { return nil }
        entries[kind] = (position + 8)..<(position + length)
        position += length
      }
      if let firstImage = file.uint32(at: header.lowerBound + 0x6C), firstImage != .max,
        let offset = entries[AZW3Metadata.coverEntry].flatMap({ file.uint32(at: $0.lowerBound) }),
        offset != .max
      {
        cover = record(Int(firstImage) + Int(offset))
      }
    }
  }
}

extension [UInt8] {
  fileprivate func uint16(at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= count else { return nil }
    return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
  }

  fileprivate func uint32(at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= count else { return nil }
    return self[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
  }
}
