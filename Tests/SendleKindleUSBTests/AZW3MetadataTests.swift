import Foundation
import SendleKindleUSB
import Testing

struct AZW3MetadataTests {
  let cover = makeJPEG(width: 80, height: 110)

  @Test func readsWhatTheKindlesLibraryUses() throws {
    let metadata = try #require(AZW3Metadata(makeAZW3(asin: "EBOK000000", cover: cover)))

    #expect(metadata == AZW3Metadata(asin: "EBOK000000", documentType: "EBOK", cover: cover))
  }

  @Test func aBookWithoutACoverHasNone() throws {
    #expect(try #require(AZW3Metadata(makeAZW3())).cover == nil)
  }

  @Test func readsNothingFromAFileThatIsNotAKindleBook() {
    #expect(AZW3Metadata(Data("epub".utf8)) == nil)
    #expect(AZW3Metadata(makeAZW3().prefix(100)) == nil)
  }

  @Test func replacesTheASINWithoutMovingAnythingElse() throws {
    let book = makeAZW3(asin: "EBOK000000", cover: cover)

    let patched = try #require(AZW3Metadata.replacingASIN(in: book, with: "SN2Q7KXA4B"))

    #expect(patched.count == book.count)
    #expect(
      AZW3Metadata(patched) == AZW3Metadata(asin: "SN2Q7KXA4B", documentType: "EBOK", cover: cover))
    #expect(zip(book, patched).filter { $0.0 != $0.1 }.count <= 10)
  }

  @Test func keepsTheASINWhenTheNewOneIsAnotherLength() {
    #expect(AZW3Metadata.replacingASIN(in: makeAZW3(asin: "EBOK000000"), with: "SHORT") == nil)
  }

  @Test func makesAnASINOfTheBooksNameThatAmazonDoesNotUse() {
    let asin = AZW3Metadata.asin(for: "Moby-Dick - Herman Melville")

    #expect(asin.count == 10)
    #expect(asin.hasPrefix("SN"))
    #expect(asin.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) })
    #expect(AZW3Metadata.asin(for: "Moby-Dick - Herman Melville") == asin)
    #expect(AZW3Metadata.asin(for: "Dracula - Bram Stoker") != asin)
  }
}
