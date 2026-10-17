import Foundation
import SMTPKit
import SendleDomain
import SendleMail
import SendleTestSupport
import Testing
import os

@Suite(.timeLimit(.minutes(1)))
struct EmailDeliveryChannelTests {
  typealias Read = ScriptedSMTPTransport.Read

  let folder: URL
  let greeting = Read.code(220, "smtp.gmail.com ESMTP")
  /// "\0me@gmail.com\0app-password"
  let plainToken = "AG1lQGdtYWlsLmNvbQBhcHAtcGFzc3dvcmQ="

  init() throws {
    folder = try makeTemporaryDirectory()
  }

  func ehlo(size: Int? = nil) -> Read {
    .reply(
      SMTPReply(
        code: 250,
        lines: ["smtp.gmail.com", "AUTH LOGIN PLAIN"] + (size.map { ["SIZE \($0)"] } ?? [])))
  }

  func accepting(size: Int? = nil) -> [Read] {
    [
      greeting, ehlo(size: size), .code(235, "Accepted"), .code(250, "OK"), .code(250, "OK"),
      .code(354, "Go ahead"), .code(250, "OK queued"), .code(221, "Bye"),
    ]
  }

  func file(_ format: FileFormat = .epub, bytes: Int = 2_000) throws -> PreparedFile {
    let url = folder.appending(path: "book-\(UUID().uuidString).\(format.fileExtension)")
    try Data((0..<bytes).map { UInt8($0 % 256) }).write(to: url)
    return PreparedFile(url: url, format: format)
  }

  func channel(
    _ transport: ScriptedSMTPTransport,
    email: EmailSettings = .fixture,
    servers: OSAllocatedUnfairLock<[SMTPServer]> = OSAllocatedUnfairLock(initialState: [])
  ) -> EmailDeliveryChannel {
    EmailDeliveryChannel(
      email: email, recipient: .fixture, password: "app-password",
      makeTransport: { server in
        servers.withLock { $0.append(server) }
        return transport
      },
      now: { Date(timeIntervalSince1970: 1_792_159_500) })
  }

  func deliver(
    _ file: PreparedFile,
    with transport: ScriptedSMTPTransport,
    email: EmailSettings = .fixture
  ) async -> SendFailure? {
    do {
      try await channel(transport, email: email).deliver(file, named: "Moby-Dick - Herman Melville")
      { _ in }
      return nil
    } catch {
      return error
    }
  }

  // MARK: The message

  @Test func sendsTheBookAsAnAttachmentNamedAfterIt() async throws {
    let transport = ScriptedSMTPTransport(accepting())

    #expect(await deliver(try file(), with: transport) == nil)

    let written = transport.written
    let message = written.drop { $0 != "DATA\r\n" }.dropFirst().joined()
    #expect(written.contains("AUTH PLAIN \(plainToken)\r\n"))
    #expect(written.contains { $0.hasPrefix("MAIL FROM:<me@gmail.com>") })
    #expect(written.contains("RCPT TO:<reader@kindle.com>\r\n"))
    #expect(message.contains("Subject: Moby-Dick - Herman Melville\r\n"))
    #expect(message.contains("filename=\"Moby-Dick - Herman Melville.epub\""))
    #expect(transport.written.last == "QUIT\r\n")
  }

  @Test(arguments: [
    (FileFormat.epub, "application/epub+zip"), (.pdf, "application/pdf"),
    (.txt, "text/plain; charset=utf-8"),
  ])
  func labelsEachFormatWithItsContentType(format: FileFormat, contentType: String) async throws {
    let transport = ScriptedSMTPTransport(accepting())

    _ = await deliver(try file(format), with: transport)

    #expect(transport.written.joined().contains("Content-Type: \(contentType);\r\n name="))
  }

  @Test func connectsTheWayTheServerIsSetUp() async throws {
    let iCloud = EmailSettings(
      kindleAddress: .fixture, senderAddress: "me@icloud.com", provider: .iCloud,
      server: SMTPServer(host: "smtp.mail.me.com", port: 587, security: .startTLS))
    let transport = ScriptedSMTPTransport([
      greeting, .code(250, "smtp.mail.me.com", "STARTTLS"), .code(220, "Ready"),
      .code(250, "smtp.mail.me.com", "AUTH PLAIN"), .code(235, "OK"), .code(250, "OK"),
      .code(250, "OK"), .code(354, "Go"), .code(250, "OK"),
    ])
    let servers = OSAllocatedUnfairLock<[SMTPServer]>(initialState: [])

    try await channel(transport, email: iCloud, servers: servers).deliver(try file(), named: "Book")
    { _ in }

    #expect(transport.events.contains(.upgradeToTLS))
    #expect(servers.withLock { $0 } == [iCloud.server])
  }

  @Test func reportsUploadProgress() async throws {
    let transport = ScriptedSMTPTransport(accepting())
    let progress = Recorder<Double>()

    try await channel(transport).deliver(try file(bytes: 200_000), named: "Book") {
      await progress.record($0)
    }

    #expect(await progress.values.first == 0)
    #expect(await progress.values.last == 1)
  }

  @Test func neverPrintsThePassword() {
    let channel = channel(ScriptedSMTPTransport([]))
    var dumped = ""
    dump(channel, to: &dumped)

    for text in [String(describing: channel), String(reflecting: channel), "\(channel)", dumped] {
      #expect(!text.contains("app-password"))
      #expect(text.contains("<redacted>"))
      #expect(text.contains("reader@kindle.com"))
    }
  }

  // MARK: Size

  @Test func refusesAFileOverAmazonsLimitWithoutConnecting() async throws {
    let url = folder.appending(path: "large.pdf")
    #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 50_000_001)
    try handle.close()
    let transport = ScriptedSMTPTransport(accepting())

    let failure = await deliver(PreparedFile(url: url, format: .pdf), with: transport)

    #expect(failure == .tooLarge(bytes: 50_000_001, limit: FormatPolicy.emailSizeLimit))
    #expect(transport.events.isEmpty)
  }

  @Test func refusesAMessageOverTheServersLimitBeforeSigningIn() async throws {
    let transport = ScriptedSMTPTransport(accepting(size: 2_000))

    let failure = await deliver(try file(bytes: 3_000), with: transport)

    guard case .tooLarge(let bytes, let limit) = failure else {
      Issue.record("Expected tooLarge, got \(String(describing: failure))")
      return
    }
    #expect(bytes == 3_000)
    #expect((1..<2_000).contains(limit))
    #expect(!transport.written.contains { $0.hasPrefix("AUTH") })
  }

  @Test func aFileOfTheReportedLimitFits() async throws {
    let first = await deliver(
      try file(bytes: 30_000), with: ScriptedSMTPTransport(accepting(size: 20_000)))
    guard case .tooLarge(_, let limit) = first else {
      Issue.record("Expected tooLarge, got \(String(describing: first))")
      return
    }

    let fitting = await deliver(
      try file(bytes: Int(limit)), with: ScriptedSMTPTransport(accepting(size: 20_000)))
    let tooBig = await deliver(
      try file(bytes: Int(limit) + 3), with: ScriptedSMTPTransport(accepting(size: 20_000)))

    #expect(fitting == nil)
    #expect(tooBig != nil)
  }

  // MARK: Failures

  @Test(
    arguments: [
      (
        2, Read.code(535, "5.7.8 Username and Password not accepted"),
        SendFailure.authenticationFailed(.gmail)
      ),
      (
        2, .code(534, "5.7.9 Application-specific password required"), .authenticationFailed(.gmail)
      ),
      (0, .code(421, "4.7.0 Try again later"), .connectionFailed(host: "smtp.gmail.com")),
      (
        6, .code(451, "4.3.0 Mail server temporarily rejected message"),
        .connectionFailed(host: "smtp.gmail.com")
      ),
      (4, .code(550, "5.1.1 No such user"), .rejected("550 5.1.1 No such user")),
      (2, .code(504, "5.5.4 Unknown"), .mailSetup("The server refused the sign-in (504).")),
      (
        1, .code(250, "smtp.gmail.com", "AUTH XOAUTH2"),
        .mailSetup("smtp.gmail.com doesn't accept an app password.")
      ),
      (
        0, .fail(.untrusted("-9843")),
        .mailSetup(
          "Sendle couldn't confirm it was talking to smtp.gmail.com, so it didn't connect. "
            + "Check the server and its security.")
      ),
      (0, .fail(.failed("refused")), .connectionFailed(host: "smtp.gmail.com")),
      (5, .fail(.timedOut), .connectionFailed(host: "smtp.gmail.com")),
      (6, .fail(.closed), .unconfirmed(host: "smtp.gmail.com")),
      (6, .fail(.timedOut), .unconfirmed(host: "smtp.gmail.com")),
      (6, .fail(.untrusted("-9806")), .unconfirmed(host: "smtp.gmail.com")),
    ] as [(Int, Read, SendFailure)])
  func explainsWhatWentWrong(position: Int, read: Read, failure: SendFailure) async throws {
    var reads = accepting()
    reads[position] = read

    #expect(await deliver(try file(), with: ScriptedSMTPTransport(reads)) == failure)
  }

  @Test func keepsOnlyTheCodeOfARefusedSignIn() async throws {
    var reads = accepting()
    reads[2] = .code(501, "5.5.2 Cannot decode AUTH PLAIN \(plainToken)")
    let echo = SMTPError.reply(
      SMTPReply(code: 535, lines: ["AUTH PLAIN \(plainToken)"]), stage: .authentication)
    let other = SMTPError.reply(SMTPReply(code: 550, lines: ["No"]), stage: .recipient)

    let failure = await deliver(try file(), with: ScriptedSMTPTransport(reads))

    #expect(failure == .mailSetup("The server refused the sign-in (501)."))
    #expect(echo.logDescription == "reply 535 at authentication")
    #expect(other.logDescription == String(describing: other))
  }

  @Test func neverSendsThePasswordWithoutTLS() async throws {
    let plain = EmailSettings(
      kindleAddress: .fixture, senderAddress: "me@example.com", provider: .custom,
      server: SMTPServer(host: "mail.example.com", port: 587, security: .startTLS))
    let transport = ScriptedSMTPTransport([greeting, .code(250, "mail.example.com", "AUTH PLAIN")])

    let failure = await deliver(try file(), with: transport, email: plain)

    #expect(
      failure
        == .mailSetup(
          "mail.example.com doesn't offer a secure connection, so Sendle didn't send your password."
        ))
  }

  @Test func dropsABrokenConnectionWithoutWaitingToSayGoodbye() async throws {
    var reads = accepting()
    reads[5] = .fail(.timedOut)
    let transport = ScriptedSMTPTransport(reads)

    _ = await deliver(try file(), with: transport)

    #expect(!transport.written.contains("QUIT\r\n"))
    #expect(transport.events.last == .close)
  }

  @Test func aMissingFileIsMissing() async {
    let transport = ScriptedSMTPTransport(accepting())

    let failure = await deliver(
      PreparedFile(url: folder.appending(path: "gone.epub"), format: .epub), with: transport)

    #expect(failure == .missing)
  }

  @Test func stopsWhenItsTaskIsCancelled() async throws {
    var reads = accepting()
    reads[5] = .hang
    let transport = ScriptedSMTPTransport(reads)
    let book = try file()
    let delivery = Task { await deliver(book, with: transport) }

    await transport.waitUntilHanging()
    delivery.cancel()

    #expect(await delivery.value == .cancelled)
  }

  @Test func aCancelAfterTheWholeBookWasSentIsUnconfirmed() async throws {
    var reads = accepting()
    reads[6] = .hang
    let transport = ScriptedSMTPTransport(reads)
    let book = try file()
    let delivery = Task { await deliver(book, with: transport) }

    await transport.waitUntilHanging()
    delivery.cancel()

    #expect(await delivery.value == .unconfirmed(host: "smtp.gmail.com"))
  }
}
