import SendleKindleUSB
import Testing

struct SendleASINSchemeTests {
  @Test func theSchemeIsSendlesASIN() {
    #expect(
      SendleASINScheme().asin(forSeed: "edition:urn:uuid:moby-dick")
        == AZW3Metadata.asin(for: "edition:urn:uuid:moby-dick"))
  }
}
