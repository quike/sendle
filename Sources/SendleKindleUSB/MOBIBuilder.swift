import Foundation

/// Builds the smallest MOBI-family book a Kindle's headers can be read from: a PalmDB with
/// record 0 (PalmDOC, MOBI and EXTH headers), one text record and, with a cover, one image record.
package enum MOBIBuilder {
  /// `exth` entries are written in order; a cover adds entry 201 and the first image index.
  package static func book(
    fullName: String = "Book",
    exth: [(UInt32, String)],
    cover: Data? = nil,
    encryption: UInt16 = 0
  ) -> Data {
    var entries = exth.map { ($0.0, Data($0.1.utf8)) }
    if cover != nil { entries.append((201, bigEndian(UInt32(0)))) }
    var body = Data()
    for (kind, value) in entries {
      body += bigEndian(kind) + bigEndian(UInt32(8 + value.count)) + value
    }
    var exthSection =
      Data("EXTH".utf8) + bigEndian(UInt32(12 + body.count)) + bigEndian(UInt32(entries.count))
      + body
    exthSection += Data(count: (4 - exthSection.count % 4) % 4)
    let name = Data(fullName.utf8)

    var palmDoc = Data(count: 16)
    palmDoc.replaceSubrange(12..<14, with: bigEndian(encryption))
    var mobi = Data(count: 0xE8)
    mobi.replaceSubrange(0..<4, with: Data("MOBI".utf8))
    mobi.replaceSubrange(4..<8, with: bigEndian(UInt32(0xE8)))
    mobi.replaceSubrange(0x44..<0x48, with: bigEndian(UInt32(16 + 0xE8 + exthSection.count)))
    mobi.replaceSubrange(0x48..<0x4C, with: bigEndian(UInt32(name.count)))
    mobi.replaceSubrange(0x5C..<0x60, with: bigEndian(cover == nil ? UInt32.max : 2))
    mobi.replaceSubrange(0x70..<0x74, with: bigEndian(UInt32(0x40)))
    let record0 = palmDoc + mobi + exthSection + name + Data(count: 4)
    let records = [record0, Data("<html>text</html>".utf8)] + (cover.map { [$0] } ?? [])

    var file = Data(count: 78)
    file.replaceSubrange(0..<5, with: Data("Book\0".utf8))
    file.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
    file.replaceSubrange(76..<78, with: bigEndian(UInt16(records.count)))
    var offset = 78 + 8 * records.count + 2
    for (index, record) in records.enumerated() {
      file += bigEndian(UInt32(offset)) + bigEndian(UInt32(index * 2))
      offset += record.count
    }
    file += Data(count: 2)
    for record in records { file += record }
    return file
  }

  private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }
}
