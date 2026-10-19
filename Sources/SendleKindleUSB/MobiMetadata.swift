import Foundation

/// What a MOBI-family book (MOBI, AZW, AZW3) says about itself, read from its headers alone.
package struct MobiMetadata: Hashable, Sendable {
  package let title: String?
  package let authors: [String]
  package let asin: String?
  /// "EBOK" for a book, "PDOC" for a personal document.
  package let documentType: String?
  /// As the book wrote it, so not yet normalised.
  package let isbn: String?
  package let publisher: String?
  package let isEncrypted: Bool
  package let coverRecord: Range<Int>?

  /// Nil unless `source` is a Kindle book with an EXTH header.
  package init?(_ source: some ByteSource) {
    guard let layout = MobiLayout(source), let flags = layout.record0.uint32(at: 0x80),
      flags & 0x40 != 0
    else { return nil }
    func texts(_ kind: UInt32) -> [String] {
      (layout.entries[kind] ?? []).map { range in
        String(
          decoding: layout.record0[
            (range.lowerBound - layout.record0Start)..<(range.upperBound - layout.record0Start)],
          as: UTF8.self
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
      }.filter { !$0.isEmpty }
    }
    func text(_ kind: UInt32) -> String? { texts(kind).last }

    title = text(503) ?? Self.fullName(in: layout)
    authors = texts(100)
    asin = text(113) ?? text(504)
    documentType = text(501)
    isbn = text(104)
    publisher = text(101)
    isEncrypted = (layout.record0.uint16(at: 12) ?? 0) != 0
    coverRecord = layout.cover
  }

  private static func fullName(in layout: MobiLayout) -> String? {
    guard let offset = layout.record0.uint32(at: 0x54).map(Int.init),
      let length = layout.record0.uint32(at: 0x58).map(Int.init),
      offset + length <= layout.record0.count
    else { return nil }
    let name = String(decoding: layout.record0[offset..<(offset + length)], as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
  }
}
