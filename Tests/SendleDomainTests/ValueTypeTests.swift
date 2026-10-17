import Foundation
import SendleDomain
import SendleTestSupport
import Testing

struct KindleEmailTests {
  @Test(arguments: ["reader@kindle.com", "Reader@Kindle.COM", "reader_123@kindle.cn"])
  func recognisesAmazonAddresses(address: String) {
    #expect(KindleEmail(rawValue: address).isAmazonAddress)
  }

  @Test(arguments: ["reader@gmail.com", "reader@kindle.com.evil.net", "kindle.com"])
  func rejectsOtherAddresses(address: String) {
    #expect(!KindleEmail(rawValue: address).isAmazonAddress)
  }
}

struct EmailAddressTests {
  @Test(arguments: ["me@gmail.com", "first.last+kindle@icloud.com", "a@b.co"])
  func acceptsPlausibleAddresses(address: String) {
    #expect(EmailAddress.isPlausible(address))
  }

  @Test(arguments: [
    "", "me", "@gmail.com", "me@", "me@gmail", "me@@gmail.com", "me @gmail.com", "me@.com",
    "me@gmail.",
  ])
  func rejectsImplausibleAddresses(address: String) {
    #expect(!EmailAddress.isPlausible(address))
  }
}

struct FormatConverterTests {
  private struct Tool: FormatConverter {
    let toolURL: URL?

    func convert(
      _ file: PreparedFile, to format: FileFormat, in staging: URL
    ) async throws(SendFailure) -> PreparedFile {
      throw .conversionUnavailable
    }
  }

  @Test func isAvailableOnlyWhileItsToolIsInstalled() {
    #expect(
      Tool(toolURL: URL(filePath: "/Applications/calibre.app/Contents/MacOS/ebook-convert"))
        .isAvailable)
    #expect(!Tool(toolURL: nil).isAvailable)
  }
}

struct FileFormatTests {
  @Test func mimeTypesMatchWhatAmazonExpects() {
    #expect(FileFormat.epub.mimeType == "application/epub+zip")
    #expect(FileFormat.pdf.mimeType == "application/pdf")
    #expect(BookFormat.epub.fileFormat == .epub)
    #expect(BookFormat.pdf.fileFormat == .pdf)
  }

  @Test func destinationsKnowTheirKind() {
    #expect(Destination.email(.fixture).kind == .email)
    #expect(Destination.usb(.fixture()).kind == .usb)
  }
}
