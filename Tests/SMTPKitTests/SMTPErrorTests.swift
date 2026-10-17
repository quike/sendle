import SMTPKit
import Testing

struct SMTPErrorTests {
  @Test func onlyABreakWhileWaitingForTheFinalAnswerMayHaveDelivered() {
    #expect(SMTPError.connection("reset", stage: .endOfMessage).mayHaveDeliveredMessage)
    #expect(SMTPError.timedOut(.endOfMessage).mayHaveDeliveredMessage)
    #expect(SMTPError.malformedReply(.endOfMessage).mayHaveDeliveredMessage)
  }

  @Test(arguments: SMTPStage.allCases.filter { $0 != .endOfMessage })
  func aBreakBeforeTheEndOfTheMessageDeliveredNothing(stage: SMTPStage) {
    #expect(!SMTPError.connection("reset", stage: stage).mayHaveDeliveredMessage)
    #expect(!SMTPError.timedOut(stage).mayHaveDeliveredMessage)
  }

  @Test func aReplyIsAnAnswerEvenAtTheEnd() {
    let reply = SMTPReply(code: 451, lines: ["Try again later"])

    #expect(!SMTPError.reply(reply, stage: .endOfMessage).mayHaveDeliveredMessage)
  }

  @Test(
    arguments: [
      (SMTPTransportError.failed("refused"), SMTPError.connection("refused", stage: .hello)),
      (.timedOut, .timedOut(.hello)),
      (.closed, .connection("The server closed the connection", stage: .hello)),
      (.malformedReply, .malformedReply(.hello)),
      (.cancelled, .cancelled),
      (.untrusted("bad certificate"), .untrustedServer("bad certificate")),
    ] as [(SMTPTransportError, SMTPError)])
  func namesTheStageATransportFailureHappenedIn(failure: SMTPTransportError, error: SMTPError) {
    #expect(SMTPError(failure, at: .hello) == error)
  }
}
