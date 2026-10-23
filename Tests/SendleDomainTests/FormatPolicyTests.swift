import SendleDomain
import SendleTestSupport
import Testing

struct FormatPolicyTests {
  @Test(arguments: [
    (Availability.protected, SendFailure.protected),
    (.inCloudOnly, .inCloudOnly),
    (.missing, .missing),
  ])
  func unavailableBooksAreBlockedEverywhere(availability: Availability, reason: SendFailure) {
    let book = Book.fixture(availability: availability)
    for destination in DestinationKind.allCases {
      let plan = FormatPolicy.plan(for: book, to: destination, converterAvailable: true)
      #expect(plan == .blocked(reason, suggestion: nil))
    }
  }

  @Test func epubToEmailIsPreparedThenDelivered() {
    let plan = FormatPolicy.plan(
      for: .fixture(format: .epub), to: .email, converterAvailable: false)
    #expect(plan == .send([.prepareEPUB, .deliver]))
  }

  @Test func epubSizeIsLeftToTheEmailChannelBecauseZippingShrinksIt() {
    let book = Book.fixture(format: .epub, sizeBytes: 80_000_000)
    #expect(
      FormatPolicy.plan(for: book, to: .email, converterAvailable: false)
        == .send([.prepareEPUB, .deliver]))
  }

  @Test func pdfToEmailIsDeliveredAsIs() {
    let plan = FormatPolicy.plan(for: .fixture(format: .pdf), to: .email, converterAvailable: false)
    #expect(plan == .send([.deliver]))
  }

  @Test func pdfOverTheEmailLimitSuggestsUSB() {
    let book = Book.fixture(format: .pdf, sizeBytes: 62_000_000)
    let plan = FormatPolicy.plan(for: book, to: .email, converterAvailable: false)
    #expect(plan == .blocked(.tooLarge(bytes: 62_000_000, limit: 50_000_000), suggestion: .usb))
  }

  @Test func pdfExactlyAtTheEmailLimitIsAllowed() {
    let book = Book.fixture(format: .pdf, sizeBytes: FormatPolicy.emailSizeLimit)
    #expect(
      FormatPolicy.plan(for: book, to: .email, converterAvailable: false) == .send([.deliver]))
  }

  @Test func pdfOfUnknownSizeIsAllowed() {
    let book = Book.fixture(format: .pdf, sizeBytes: nil)
    #expect(
      FormatPolicy.plan(for: book, to: .email, converterAvailable: false) == .send([.deliver]))
  }

  @Test func pdfToUSBIsCopiedAsIsWhateverItsSize() {
    let book = Book.fixture(format: .pdf, sizeBytes: 900_000_000)
    #expect(FormatPolicy.plan(for: book, to: .usb, converterAvailable: false) == .send([.deliver]))
  }

  @Test func epubToUSBIsConvertedWhenAConverterIsInstalled() {
    let plan = FormatPolicy.plan(for: .fixture(format: .epub), to: .usb, converterAvailable: true)
    #expect(plan == .send([.prepareEPUB, .convert(to: .azw3), .deliver]))
  }

  @Test func epubToUSBWithoutAConverterSuggestsEmail() {
    let plan = FormatPolicy.plan(for: .fixture(format: .epub), to: .usb, converterAvailable: false)
    #expect(plan == .blocked(.conversionUnavailable, suggestion: .email))
  }
}
