import Foundation
import SMTPKit
import Testing

struct MessageDataTests {
  func terminated(_ text: String) -> String {
    String(decoding: MessageData.terminated(Data(text.utf8)), as: UTF8.self)
  }

  @Test func doublesTheDotThatStartsALine() {
    #expect(terminated(".hidden\r\nok\r\n..two\r\n") == "..hidden\r\nok\r\n...two\r\n.\r\n")
  }

  @Test func leavesDotsInsideALineAlone() {
    #expect(terminated("a.b.\r\n") == "a.b.\r\n.\r\n")
  }

  @Test func aLoneDotLineCannotEndTheMessageEarly() {
    #expect(terminated("a\r\n.\r\nb\r\n") == "a\r\n..\r\nb\r\n.\r\n")
  }

  @Test func endsAnUnfinishedLastLine() {
    #expect(terminated("abc") == "abc\r\n.\r\n")
  }
}
