import Foundation
import SendleUI
import Testing

struct TextMatchesTests {
  func matches(_ words: [Substring], in text: String) -> [String] {
    TextMatches.ranges(of: words, in: text).map { String(text[$0]) }
  }

  @Test func findsEveryWordWhateverItsCase() {
    #expect(matches(["MOBY", "kin"], in: "Sent moby to kindle") == ["moby", "kin"])
  }

  @Test func ignoresAccents() {
    #expect(matches(["bronte"], in: "Charlotte Brontë") == ["Brontë"])
  }

  @Test func findsEveryOccurrence() {
    #expect(matches(["a"], in: "banana") == ["a", "a", "a"])
  }

  @Test func mergesOverlappingRanges() {
    #expect(matches(["abc", "bc"], in: "abcd") == ["abc"])
  }

  @Test func mergesTouchingRanges() {
    #expect(matches(["ab", "cd"], in: "abcd") == ["abcd"])
  }

  @Test func givesNothingWithoutWords() {
    #expect(TextMatches.ranges(of: [], in: "banana").isEmpty)
  }

  @Test func givesNothingWhenNoWordIsThere() {
    #expect(matches(["kobo"], in: "Sent moby to kindle").isEmpty)
  }

  @Test func containsOnlyWithEveryWord() {
    #expect(TextMatches.contains(every: ["moby", "KINDLE"], in: "Sent moby to kindle"))
    #expect(!TextMatches.contains(every: ["moby", "kobo"], in: "Sent moby to kindle"))
    #expect(TextMatches.contains(every: [], in: "Sent moby to kindle"))
  }
}
