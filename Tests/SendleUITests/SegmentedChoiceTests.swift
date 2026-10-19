import CoreGraphics
import SendleUI
import Testing

struct SegmentedChoiceTests {
  let choice = SegmentedChoice(options: ["Full", "Compact", "Off"], selection: "Compact")

  @Test func theSelectedOptionIsFoundAmongTheOptions() {
    #expect(choice.index == 1)
    #expect(SegmentedChoice(options: ["A", "B"], selection: "C").index == 0)
  }

  @Test func eachOptionTakesAnEqualShareOfTheTrack() {
    #expect(choice.segmentWidth(in: 150) == 50)
  }

  @Test func theHighlightSitsUnderTheSelectedOption() {
    #expect(choice.highlightOffset(in: 150) == 50)
    let first = SegmentedChoice(options: ["Full", "Compact", "Off"], selection: "Full")
    #expect(first.highlightOffset(in: 150) == 0)
    let last = SegmentedChoice(options: ["Full", "Compact", "Off"], selection: "Off")
    #expect(last.highlightOffset(in: 150) == 100)
  }

  @Test func steppingMovesToTheNeighbouringOption() {
    #expect(choice.stepped(forward: true) == "Off")
    #expect(choice.stepped(forward: false) == "Full")
  }

  @Test func steppingStopsAtEitherEnd() {
    let first = SegmentedChoice(options: ["Full", "Compact"], selection: "Full")
    #expect(first.stepped(forward: false) == "Full")
    let last = SegmentedChoice(options: ["Full", "Compact"], selection: "Compact")
    #expect(last.stepped(forward: true) == "Compact")
  }
}
