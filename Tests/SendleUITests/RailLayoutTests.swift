import SendleUI
import Testing

struct RailLayoutTests {
  let letters = ["A", "B", "C", "D"]

  @Test func findsTheLetterUnderThePointer() {
    #expect(RailLayout.letter(at: 0, height: 100, letters: letters) == "A")
    #expect(RailLayout.letter(at: 30, height: 100, letters: letters) == "B")
    #expect(RailLayout.letter(at: 99, height: 100, letters: letters) == "D")
  }

  @Test func aDragPastEitherEndStaysOnTheEndLetter() {
    #expect(RailLayout.letter(at: -40, height: 100, letters: letters) == "A")
    #expect(RailLayout.letter(at: 400, height: 100, letters: letters) == "D")
  }

  @Test func anEmptyRailHasNoLetter() {
    #expect(RailLayout.letter(at: 10, height: 100, letters: []) == nil)
    #expect(RailLayout.letter(at: 10, height: 0, letters: letters) == nil)
  }
}
