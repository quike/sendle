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
