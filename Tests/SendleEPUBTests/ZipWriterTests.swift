import Foundation
import SendleEPUB
import SendleTestSupport
import Testing

struct CRC32Tests {
  @Test func matchesTheStandardCheckValues() {
    #expect(CRC32.checksum(Data()) == 0)
    #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    #expect(CRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
  }
}

struct ZipWriterTests {
  let folder: URL
  let archive: URL
  let text = Data(String(repeating: "Call me Ishmael. ", count: 500).utf8)
  let noise = Data((0..<4_096).map { _ in UInt8.random(in: 0...255) })

  init() throws {
    folder = try makeTemporaryDirectory()
    archive = folder.appending(path: "book.epub")
  }

  @Test func putsTheMimetypeFirstStoredAndWithoutAnExtraField() throws {
    try writeArchive(
      [("mimetype", Data("application/epub+zip".utf8)), ("OEBPS/chapter1.xhtml", text)],
      to: archive)

    let bytes = try Data(contentsOf: archive)

    #expect(bytes.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    #expect(bytes.uint16(at: 8) == 0)  // stored
    #expect(bytes.uint16(at: 28) == 0)  // no extra field
    #expect(String(decoding: bytes[30..<58], as: UTF8.self) == "mimetypeapplication/epub+zip")
  }

  @Test func deflatesWhatShrinksAndStoresTheRest() throws {
    try writeArchive(
      [
        ("mimetype", Data("application/epub+zip".utf8)), ("text.xhtml", text), ("noise.jpg", noise),
      ],
      to: archive)

    let headers = localHeaders(in: try Data(contentsOf: archive))

    #expect(headers.map(\.name) == ["mimetype", "text.xhtml", "noise.jpg"])
    #expect(headers.map(\.method) == [0, 8, 0])
    #expect(headers[1].compressedSize < text.count)
    #expect(headers.allSatisfy { $0.extraLength == 0 })
  }

  @Test func recordsEachFilesChecksumAndSize() throws {
    try writeArchive(
      [("mimetype", Data("application/epub+zip".utf8)), ("text.xhtml", text)], to: archive)

    let header = try #require(localHeaders(in: try Data(contentsOf: archive)).last)

    #expect(header.crc == CRC32.checksum(text))
    #expect(header.size == text.count)
  }

  @Test func stampsEntriesWithTheGregorianDateAndTime() throws {
    let calendar = Calendar(identifier: .gregorian)
    let modified = try #require(
      calendar.date(
        from: DateComponents(year: 2027, month: 1, day: 15, hour: 13, minute: 45, second: 30)))
    let writer = try ZipWriter(creatingFileAt: archive, modified: modified)
    try writer.add("mimetype", data: Data("application/epub+zip".utf8), method: .stored)
    try writer.finish()

    let bytes = try Data(contentsOf: archive)

    #expect(bytes.uint16(at: 10) == 13 << 11 | 45 << 5 | 30 / 2)
    #expect(bytes.uint16(at: 12) == (2027 - 1980) << 9 | 1 << 5 | 15)
  }

  @Test func marksNonASCIINamesAsUTF8() throws {
    try writeArchive(
      [("mimetype", Data("application/epub+zip".utf8)), ("Capítulo 1.xhtml", text)], to: archive)

    let headers = localHeaders(in: try Data(contentsOf: archive))

    #expect(headers.map(\.flags) == [0, 0x0800])
  }

  @Test func passesUnzipsIntegrityCheck() throws {
    try writeArchive(
      [
        ("mimetype", Data("application/epub+zip".utf8)), ("OEBPS/text.xhtml", text),
        ("noise.jpg", noise), ("empty.css", Data()),
      ],
      to: archive)

    let result = try run("/usr/bin/unzip", ["-t", archive.path(percentEncoded: false)])

    #expect(result.status == 0)
    #expect(result.output.contains("No errors detected"))
  }

  @Test func unzipsBackToTheSameFiles() throws {
    let files = [
      ("mimetype", Data("application/epub+zip".utf8)), ("OEBPS/Capítulo 1.xhtml", text),
      ("OEBPS/images/noise.jpg", noise),
    ]
    try writeArchive(files, to: archive)
    let out = folder.appending(path: "out", directoryHint: .isDirectory)

    let result = try run(
      "/usr/bin/ditto",
      ["-x", "-k", archive.path(percentEncoded: false), out.path(percentEncoded: false)])

    #expect(result.status == 0)
    for (name, data) in files {
      #expect(try Data(contentsOf: out.appending(path: name)) == data)
    }
  }

  @Test func refusesValuesBeyondTheClassicFormat() throws {
    #expect(try ZipWriter.field32(0xFFFF_FFFE) == 0xFFFF_FFFE)
    #expect(throws: ZipError.tooLarge) { try ZipWriter.field32(0xFFFF_FFFF) }
    #expect(throws: ZipError.tooLarge) { try ZipWriter.field32(-1) }
  }

  @Test func reportsAnUnwritableDestination() {
    #expect(throws: ZipError.cannotWrite("Couldn't create the archive file")) {
      try ZipWriter(creatingFileAt: folder.appending(path: "missing/book.epub"))
    }
  }
}
