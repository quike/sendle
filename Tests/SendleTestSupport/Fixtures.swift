import Foundation
import SendleDomain

extension Book {
  public static func fixture(
    id: String = "book-1",
    title: String = "Moby-Dick",
    author: String? = "Herman Melville",
    language: String? = "en",
    format: BookFormat = .epub,
    sizeBytes: Int64? = 1_000_000,
    addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    isStorePurchase: Bool = false,
    availability: Availability = .ready
  ) -> Book {
    Book(
      id: BookID(rawValue: id),
      title: title,
      author: author,
      language: language,
      format: format,
      fileURL: URL(filePath: "/Books/\(id).\(format.rawValue)"),
      sizeBytes: sizeBytes,
      addedAt: addedAt,
      isStorePurchase: isStorePurchase,
      availability: availability
    )
  }
}

extension KindleEmail {
  public static let fixture = KindleEmail(rawValue: "reader@kindle.com")
}

extension KindleVolume {
  public static func fixture(name: String = "Kindle") -> KindleVolume {
    KindleVolume(id: name, name: name, mountURL: URL(filePath: "/Volumes/\(name)"))
  }
}
