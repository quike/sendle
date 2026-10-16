import Foundation
import SMTPKit
import Testing

/// Talks to a real server. `SENDLE_TEST_SMTP_HOST` and `_PORT` enable the connection check;
/// `_USER`, `_PASS` and `_TO` also send a short text message. Port 465 means implicit TLS.
@Suite(.timeLimit(.minutes(2)))
struct LiveSMTPCheck {
  static let environment = ProcessInfo.processInfo.environment
  static let host = environment["SENDLE_TEST_SMTP_HOST"]
  static let port = environment["SENDLE_TEST_SMTP_PORT"].flatMap { Int($0) }
  static let user = environment["SENDLE_TEST_SMTP_USER"]
  static let password = environment["SENDLE_TEST_SMTP_PASS"]
  static let recipient = environment["SENDLE_TEST_SMTP_TO"]

  func session(host: String, port: Int) -> SMTPSession {
    SMTPSession(
      transport: StreamTaskTransport(host: host, port: port, implicitTLS: port == 465),
      startTLS: port != 465)
  }

  @Test(.enabled(if: host != nil && port != nil))
  func connectsAndReachesTLS() async throws {
    guard let host = Self.host, let port = Self.port else { return }
    let session = session(host: host, port: port)

    try await session.connect()
    let capabilities = await session.capabilities
    await session.quit()

    #expect(!capabilities.authMechanisms.isEmpty)
  }

  @Test(
    .enabled(if: host != nil && port != nil && user != nil && password != nil && recipient != nil))
  func sendsATextMessage() async throws {
    guard let host = Self.host, let port = Self.port, let user = Self.user,
      let password = Self.password, let recipient = Self.recipient
    else { return }
    let session = session(host: host, port: port)
    let message = MIMEMessage(
      from: user, to: recipient, subject: "Sendle live check", text: "Sent by Sendle's tests.",
      attachment: MIMEMessage.Attachment(
        filename: "Sendle live check.txt", contentType: "text/plain; charset=utf-8",
        data: Data("Sendle reached your mail server. You can delete this document.\n".utf8)))

    try await session.connect()
    try await session.authenticate(username: user, password: password)
    try await session.send(message.encoded(), from: user, to: [recipient]) { _ in }
    await session.quit()
  }
}
