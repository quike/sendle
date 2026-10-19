import Foundation
import SendleKindleUSB
import SendleTestSupport
import Testing

struct MobiMetadataTests {
  let cover = makeJPEG(width: 80, height: 110)
  var moby: Data {
    MOBIBuilder.book(
      fullName: "MOBYDICK",
      exth: [
        (503, "Moby-Dick"), (100, "Herman Melville"), (100, "Second Author"), (113, "SN5T2DYX77"),
        (501, "EBOK"), (104, "978-0-306-40615-7"), (101, "Penguin"),
      ], cover: cover)
  }

  @Test func readsWhatTheKindleShows() throws {
    let moby = moby
    let found = try #require(MobiMetadata(DataBytes(moby)))
    #expect(found.title == "Moby-Dick")
    #expect(found.authors == ["Herman Melville", "Second Author"])
    #expect(found.asin == "SN5T2DYX77")
    #expect(found.documentType == "EBOK")
    #expect(found.isbn == "978-0-306-40615-7")
    #expect(found.publisher == "Penguin")
    #expect(!found.isEncrypted)
    #expect(found.coverRecord.map { Data(moby[$0]) } == cover)
  }

  @Test func fallsBackToTheFullNameAndThe504ASIN() throws {
    let found = try #require(
      MobiMetadata(DataBytes(MOBIBuilder.book(fullName: "Dracula", exth: [(504, "B088BBLMGS")]))))
    #expect(found.title == "Dracula")
    #expect(found.asin == "B088BBLMGS")
  }

  @Test func aProtectedBookStillShowsTitleAuthorAndCover() throws {
    let found = try #require(
      MobiMetadata(
        DataBytes(
          MOBIBuilder.book(
            exth: [(503, "Dune"), (100, "Frank Herbert")], cover: cover, encryption: 2))))
    #expect(found.isEncrypted)
    #expect(found.title == "Dune")
    #expect(found.coverRecord != nil)
  }

  @Test func readsOnlyTheHeaderFromAFile() throws {
    let url = try makeTemporaryDirectory().appending(path: "big.azw3")
    var data = MOBIBuilder.book(exth: [(503, "Big")])
    data.append(Data(count: 5_000_000))
    try data.write(to: url)
    let file = try #require(FileBytes(url: url))
    #expect(MobiMetadata(file)?.title == "Big")
    #expect(file.bytesRead < 64_000)
  }

  @Test func aTruncatedFileReadsNothing() {
    #expect(MobiMetadata(DataBytes(moby.prefix(100))) == nil)
    #expect(MobiMetadata(DataBytes(moby.prefix(300))) == nil)
    #expect(MobiMetadata(DataBytes(Data("not a book".utf8))) == nil)
  }

  @Test func aBookWithoutTheEXTHFlagReadsNothing() throws {
    var data = MOBIBuilder.book(exth: [(503, "Dune")])
    let layout = try #require(MobiLayout(DataBytes(data)))
    data[layout.record0Start + 0x83] = 0

    #expect(MobiMetadata(DataBytes(data)) == nil)
  }

  @Test func aHugeRecordZeroIsNotReadWhole() throws {
    let url = try makeTemporaryDirectory().appending(path: "huge.azw3")
    try MOBIBuilder.book(exth: [(503, "Huge"), (999, String(repeating: "a", count: 1 << 21))])
      .write(to: url)
    let file = try #require(FileBytes(url: url))

    #expect(MobiMetadata(file) == nil)
    #expect(file.bytesRead < (1 << 20) + 64_000)
  }
}
