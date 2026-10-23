import Foundation
import SMTPKit
import Testing

struct ReplyParserTests {
  func replies(_ chunks: String...) throws -> [SMTPReply] {
    var parser = ReplyParser()
    var replies: [SMTPReply] = []
    for chunk in chunks {
      parser.append(Data(chunk.utf8))
      while let reply = try parser.nextReply() { replies.append(reply) }
    }
    return replies
  }

  @Test func readsAOneLineReply() throws {
    #expect(
      try replies("220 smtp.gmail.com ESMTP ready\r\n")
        == [SMTPReply(code: 220, lines: ["smtp.gmail.com ESMTP ready"])])
  }

  @Test func joinsTheLinesOfAMultilineReply() throws {
    let reply = try replies(
      "250-smtp.gmail.com at your service\r\n250-SIZE 35882577\r\n250 SMTPUTF8\r\n")

    #expect(
      reply == [
        SMTPReply(
          code: 250, lines: ["smtp.gmail.com at your service", "SIZE 35882577", "SMTPUTF8"])
      ])
  }

  @Test func waitsForTheRestOfAReply() throws {
    var parser = ReplyParser()
    parser.append(Data("250-first\r\n250 sec".utf8))
    #expect(try parser.nextReply() == nil)

    parser.append(Data("ond\r\n".utf8))

    #expect(try parser.nextReply() == SMTPReply(code: 250, lines: ["first", "second"]))
  }

  @Test func keepsAFollowingReplyForTheNextRead() throws {
    #expect(
      try replies("250 OK\r\n354 Go ahead\r\n")
        == [SMTPReply(code: 250, lines: ["OK"]), SMTPReply(code: 354, lines: ["Go ahead"])])
  }

  @Test func readsACodeWithoutText() throws {
    #expect(try replies("250\r\n") == [SMTPReply(code: 250, lines: [""])])
  }

  @Test func acceptsBareLineFeeds() throws {
    #expect(try replies("220 hi\n") == [SMTPReply(code: 220, lines: ["hi"])])
  }

  @Test(arguments: [
    "HTTP/1.1 400 Bad Request\r\n", "25O oops\r\n", "250*star\r\n", "250-one\r\n251 two\r\n",
    "\r\n",
  ])
  func refusesWhatIsNotAReply(text: String) {
    #expect(throws: SMTPTransportError.malformedReply) { try replies(text) }
  }

  @Test func refusesALineLongerThanAnyServerSends() {
    let endless = String(repeating: "x", count: ReplyParser.maxLineLength + 1)

    #expect(throws: SMTPTransportError.malformedReply) { try replies("250 " + endless) }
  }

  @Test func refusesAReplyThatNeverEnds() {
    let lines = String(repeating: "250-more\r\n", count: ReplyParser.maxLines + 1)

    #expect(throws: SMTPTransportError.malformedReply) { try replies(lines) }
  }

  @Test func forgetsWhatArrivedBeforeAReset() throws {
    var parser = ReplyParser()
    parser.append(Data("250-injected\r\n".utf8))

    parser.reset()
    parser.append(Data("250 clean\r\n".utf8))

    #expect(try parser.nextReply() == SMTPReply(code: 250, lines: ["clean"]))
  }
}
