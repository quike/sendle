import Foundation
import SendleUI
import Testing

struct FormattingTests {
  @Test(
    arguments: [
      (0, "0 bytes"), (1, "1 byte"), (812, "812 bytes"), (612_400, "612 KB"), (999_999, "1 MB"),
      (1_400_000, "1.4 MB"), (9_960_000, "10 MB"), (62_000_000, "62 MB"),
      (1_500_000_000, "1.5 GB"),
    ] as [(Int64, String)])
  func sizesUseDecimalUnits(bytes: Int64, expected: String) {
    #expect(Formatting.size(bytes) == expected)
  }

  @Test(
    arguments: [
      (-30, "just now"), (0, "just now"), (59, "just now"), (60, "1m ago"), (3_599, "59m ago"),
      (3_600, "1h ago"), (86_399, "23h ago"), (86_400, "1d ago"), (29 * 86_400, "29d ago"),
      (30 * 86_400, "1mo ago"), (364 * 86_400, "12mo ago"), (365 * 86_400, "1y ago"),
    ] as [(Int, String)])
  func agesAreShortAndRelative(secondsAgo: Int, expected: String) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let date = now.addingTimeInterval(-TimeInterval(secondsAgo))

    #expect(Formatting.age(of: date, now: now) == expected)
  }

  @Test func writesADayInEnglish() {
    #expect(Formatting.day(Date(timeIntervalSince1970: 1_760_270_400), in: .gmt) == "12 Oct 2025")
  }
}
