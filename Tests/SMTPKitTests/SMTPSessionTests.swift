import Foundation
import SMTPKit
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SMTPSessionTests {
  typealias Read = ScriptedSMTPTransport.Read

  let greeting = Read.code(220, "smtp.example.com ESMTP")
  let ehlo = Read.code(250, "smtp.example.com", "SIZE 35882577", "AUTH LOGIN PLAIN XOAUTH2")
  let message = Data("Subject: Hi\r\n\r\nHello\r\n".utf8)
  /// "\0me@gmail.com\0secret"
  let plainToken = "AG1lQGdtYWlsLmNvbQBzZWNyZXQ="

  func session(_ transport: ScriptedSMTPTransport, startTLS: Bool = false) -> SMTPSession {
    SMTPSession(
      transport: transport, startTLS: startTLS,
      timeouts: SMTPTimeouts(step: .seconds(30), endOfMessage: .seconds(120)))
  }

  func sendAll(_ session: SMTPSession) async throws(SMTPError) {
    try await session.connect()
    try await session.authenticate(username: "me@gmail.com", password: "secret")
    try await session.send(message, from: "me@gmail.com", to: ["reader@kindle.com"]) { _ in }
  }

  func error(_ reads: [Read], startTLS: Bool = false) async -> SMTPError? {
    do {
      try await sendAll(session(ScriptedSMTPTransport(reads), startTLS: startTLS))
      return nil
    } catch {
      return error
    }
  }

  // MARK: The conversation

  @Test func sendsAMessageFromGreetingToGoodbye() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, ehlo, .code(235, "Accepted"), .code(250, "OK"), .code(250, "OK"),
      .code(354, "Go ahead"), .code(250, "OK queued"), .code(221, "Bye"),
    ])
    let session = session(transport)

    try await sendAll(session)
    await session.quit()

    #expect(
      transport.written == [
        "EHLO [127.0.0.1]\r\n", "AUTH PLAIN \(plainToken)\r\n",
        "MAIL FROM:<me@gmail.com> SIZE=\(message.count)\r\n", "RCPT TO:<reader@kindle.com>\r\n",
        "DATA\r\n", "Subject: Hi\r\n\r\nHello\r\n.\r\n", "QUIT\r\n",
      ])
    #expect(transport.events.first == .open)
    #expect(transport.events.last == .close)
    #expect(await session.capabilities.sizeLimit == 35_882_577)
  }

  @Test func upgradesToTLSBeforeSigningIn() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, .code(250, "smtp.example.com", "STARTTLS"), .code(220, "Ready to start TLS"),
      .code(250, "smtp.example.com", "AUTH PLAIN"), .code(235, "Accepted"),
    ])
    let session = session(transport, startTLS: true)

    try await session.connect()
    try await session.authenticate(username: "me@gmail.com", password: "secret")

    let afterTLS = transport.events.drop { $0 != .upgradeToTLS }
    #expect(transport.written.prefix(2) == ["EHLO [127.0.0.1]\r\n", "STARTTLS\r\n"])
    #expect(afterTLS.contains(.write("EHLO [127.0.0.1]\r\n", timeout: .seconds(30))))
    #expect(afterTLS.contains(.write("AUTH PLAIN \(plainToken)\r\n", timeout: .seconds(30))))
    #expect(await session.capabilities.authMechanisms == ["PLAIN"])
  }

  @Test func neverSendsThePasswordWhenTLSIsNotOffered() async {
    let transport = ScriptedSMTPTransport([greeting, .code(250, "smtp.example.com", "AUTH PLAIN")])

    await #expect(throws: SMTPError.tlsUnavailable) {
      try await sendAll(session(transport, startTLS: true))
    }
    #expect(transport.written == ["EHLO [127.0.0.1]\r\n"])
  }

  @Test func signsInWithLoginWhenPlainIsNotOffered() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, .code(250, "smtp.example.com", "AUTH LOGIN"), .code(334, "VXNlcm5hbWU6"),
      .code(334, "UGFzc3dvcmQ6"), .code(235, "Accepted"),
    ])
    let session = session(transport)

    try await session.connect()
    try await session.authenticate(username: "me@gmail.com", password: "secret")

    #expect(
      transport.written.dropFirst() == ["AUTH LOGIN\r\n", "bWVAZ21haWwuY29t\r\n", "c2VjcmV0\r\n"])
  }

  @Test func refusesAServerWithoutPasswordSignIn() async {
    let reads = [greeting, .code(250, "smtp.example.com", "AUTH XOAUTH2")]

    #expect(await error(reads) == .authenticationUnavailable)
  }

  @Test func asksForASizeOnlyWhenTheServerHasALimit() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, .code(250, "smtp.example.com", "AUTH PLAIN"), .code(235, "OK"), .code(250, "OK"),
    ])
    let session = session(transport)
    try await session.connect()
    try await session.authenticate(username: "me@gmail.com", password: "secret")

    _ = try? await session.send(message, from: "me@gmail.com", to: ["reader@kindle.com"]) { _ in }

    #expect(transport.written.contains("MAIL FROM:<me@gmail.com>\r\n"))
  }

  @Test func doublesTheDotThatStartsALineOfTheMessage() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, ehlo, .code(250, "OK"), .code(250, "OK"), .code(354, "Go"), .code(250, "OK"),
    ])
    let session = session(transport)
    try await session.connect()

    try await session.send(Data(".hidden\r\nshown".utf8), from: "a@b.co", to: ["c@d.co"]) { _ in }

    #expect(transport.written.last == "..hidden\r\nshown\r\n.\r\n")
  }

  @Test func refusesAnAddressThatCouldInjectACommand() async throws {
    let transport = ScriptedSMTPTransport([greeting, ehlo])
    let session = session(transport)
    try await session.connect()

    await #expect(throws: SMTPError.invalidAddress) {
      try await session.send(message, from: "me@gmail.com\r\nRCPT TO:<x@y.z>", to: ["c@d.co"]) {
        _ in
      }
    }
    #expect(transport.written == ["EHLO [127.0.0.1]\r\n"])
  }

  // MARK: Failures

  @Test(
    arguments: [
      (1, Read.code(554, "No service"), SMTPStage.greeting),
      (2, .code(500, "Unknown command"), .hello),
      (3, .code(535, "5.7.8 Bad credentials"), .authentication),
      (4, .code(550, "Sender refused"), .sender),
      (5, .code(550, "No such user"), .recipient),
      (6, .code(451, "Try later"), .data),
      (7, .code(552, "Message too big"), .endOfMessage),
    ] as [(Int, Read, SMTPStage)])
  func namesTheReplyThatEndedTheConversation(position: Int, failure: Read, stage: SMTPStage) async {
    var reads = [
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"),
      .code(250, "OK"),
    ]
    reads[position - 1] = failure
    guard case .reply(let reply) = failure else { return }

    #expect(await error(reads) == .reply(reply, stage: stage))
  }

  @Test func namesTheStageThatTimedOut() async {
    #expect(await error([.fail(.timedOut)]) == .timedOut(.greeting))
    #expect(await error([greeting, ehlo, .fail(.timedOut)]) == .timedOut(.authentication))
  }

  @Test func aBreakWhileWritingTheMessageDeliveredNothing() async {
    let reads = [
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"),
    ]
    let transport = ScriptedSMTPTransport(reads, failingWrite: (index: 5, error: .failed("reset")))
    let session = session(transport)

    var thrown: SMTPError?
    do {
      try await session.connect()
      try await session.authenticate(username: "me@gmail.com", password: "secret")
      try await session.send(Data(count: 40_000), from: "me@gmail.com", to: ["reader@kindle.com"]) {
        _ in
      }
    } catch {
      thrown = error
    }

    #expect(thrown == .connection("reset", stage: .message))
    #expect(thrown?.mayHaveDeliveredMessage == false)
  }

  @Test func aBreakWhileWritingTheLastChunkMayHaveDeliveredIt() async {
    let reads = [
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"),
    ]
    let transport = ScriptedSMTPTransport(reads, failingWrite: (index: 5, error: .failed("reset")))

    var thrown: SMTPError?
    do { try await sendAll(session(transport)) } catch { thrown = error }

    #expect(thrown == .connection("reset", stage: .endOfMessage))
    #expect(thrown?.mayHaveDeliveredMessage == true)
  }

  @Test func aCancelWhileWaitingForTheAnswerMayHaveDeliveredIt() async {
    let transport = ScriptedSMTPTransport([
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"), .hang,
    ])
    let session = session(transport)
    let task = Task { try await sendAll(session) }

    await transport.waitUntilHanging()
    task.cancel()

    var thrown: SMTPError?
    do { try await task.value } catch { thrown = error as? SMTPError }

    #expect(thrown == .connection("Cancelled before the server answered", stage: .endOfMessage))
    #expect(thrown?.mayHaveDeliveredMessage == true)
  }

  @Test func refusesToSignInUntilTLSIsUp() async {
    let transport = ScriptedSMTPTransport([greeting, .code(250, "smtp.example.com", "AUTH PLAIN")])
    let session = session(transport, startTLS: true)

    await #expect(throws: SMTPError.tlsUnavailable) { try await session.connect() }
    await #expect(throws: SMTPError.tlsUnavailable) {
      try await session.authenticate(username: "me@gmail.com", password: "secret")
    }
    #expect(transport.written == ["EHLO [127.0.0.1]\r\n"])
  }

  @Test func aBreakAfterTheWholeMessageMayHaveDeliveredIt() async {
    let reads = [
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"),
      .fail(.closed),
    ]

    let thrown = await error(reads)

    #expect(thrown == .connection("The server closed the connection", stage: .endOfMessage))
    #expect(thrown?.mayHaveDeliveredMessage == true)
  }

  @Test func givesEveryStepThirtySecondsAndTheEndOfTheMessageTwoMinutes() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, ehlo, .code(235, "OK"), .code(250, "OK"), .code(250, "OK"), .code(354, "Go"),
      .code(250, "OK"),
    ])

    try await sendAll(session(transport))

    let timeouts = transport.events.compactMap { event -> Duration? in
      switch event {
      case .read(let timeout), .write(_, let timeout): timeout
      default: nil
      }
    }
    #expect(timeouts.dropLast().allSatisfy { $0 == .seconds(30) })
    #expect(timeouts.last == .seconds(120))
  }

  @Test func reportsProgressInAboutOnePercentSteps() async throws {
    let transport = ScriptedSMTPTransport([
      greeting, ehlo, .code(250, "OK"), .code(250, "OK"), .code(354, "Go"), .code(250, "OK"),
    ])
    let session = session(transport)
    try await session.connect()
    let progress = Recorder<Double>()

    try await session.send(Data(count: 3_000_000), from: "a@b.co", to: ["c@d.co"]) {
      await progress.record($0)
    }

    let values = await progress.values
    #expect(values.first == 0)
    #expect(values.last == 1)
    #expect((100...102).contains(values.count))
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
  }

  @Test func stopsWhenItsTaskIsCancelled() async {
    let transport = ScriptedSMTPTransport([greeting, ehlo, .hang])
    let session = session(transport)
    let task = Task { try await sendAll(session) }

    await transport.waitUntilHanging()
    task.cancel()

    await #expect(throws: SMTPError.cancelled) { try await task.value }
  }

  @Test func closingSkipsTheGoodbye() async {
    let transport = ScriptedSMTPTransport([])

    await session(transport).close()

    #expect(transport.events == [.close])
  }

  @Test func quittingIgnoresABrokenConnection() async {
    let transport = ScriptedSMTPTransport([])

    await session(transport).quit()

    #expect(transport.events.last == .close)
  }
}
