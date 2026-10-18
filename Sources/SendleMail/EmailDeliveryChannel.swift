import Foundation
import SMTPKit
import SendleDomain

/// Emails one file to a Kindle address through the sender's SMTP server.
public struct EmailDeliveryChannel: DeliveryChannel {
  public typealias MakeTransport = @Sendable (SMTPServer) -> any SMTPTransport

  public static let streamTask: MakeTransport = { server in
    StreamTaskTransport(
      host: server.host, port: server.port, implicitTLS: server.security == .implicitTLS)
  }

  static let text = "Sent by Sendle."

  public let email: EmailSettings
  public let recipient: KindleEmail
  private let password: String
  private let makeTransport: MakeTransport
  private let timeouts: SMTPTimeouts
  private let now: @Sendable () -> Date
  private let log: any ActivityLog

  public init(
    email: EmailSettings,
    recipient: KindleEmail,
    password: String,
    makeTransport: @escaping MakeTransport = streamTask,
    timeouts: SMTPTimeouts = .standard,
    now: @escaping @Sendable () -> Date = { Date() },
    log: any ActivityLog = NoActivityLog()
  ) {
    self.email = email
    self.recipient = recipient
    self.password = password
    self.makeTransport = makeTransport
    self.timeouts = timeouts
    self.now = now
    self.log = log
  }

  public func deliver(
    _ file: PreparedFile,
    named baseName: String,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    let data = try Self.contents(of: file.url)
    let message = MIMEMessage(
      from: email.senderAddress, to: recipient.rawValue, subject: baseName, text: Self.text,
      attachment: MIMEMessage.Attachment(
        filename: "\(baseName).\(file.format.fileExtension)", contentType: file.format.mimeType,
        data: data),
      date: now()
    ).encoded()
    let server = email.server
    let session = SMTPSession(
      transport: makeTransport(server), startTLS: server.security == .startTLS,
      timeouts: timeouts, transcript: Self.transcript(to: log))
    log.info(
      .mail,
      "Connecting to \(server.host):\(server.port) with "
        + (server.security == .implicitTLS ? "TLS" : "STARTTLS"))
    do throws(SendFailure) {
      try await converse(in: session, message: message, fileBytes: Int64(data.count), progress)
    } catch {
      // A stuck connection would make a goodbye wait out its timeouts too.
      await session.close()
      throw error
    }
    log.info(.mail, "\(server.host) accepted the message")
    await session.quit()
  }

  /// Commands and replies are Debug, except a reply that refuses something.
  private static func transcript(to log: any ActivityLog) -> SMTPTranscript {
    { line in
      let isRefusal = (line.code ?? 0) >= 400
      log.record(
        isRefusal ? .error : .debug, .mail,
        (line.direction == .client ? "C: " : "S: ") + line.text, heading: nil)
    }
  }

  private func converse(
    in session: SMTPSession,
    message: Data,
    fileBytes: Int64,
    _ progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    try await smtp { () async throws(SMTPError) in try await session.connect() }
    if let limit = await session.capabilities.sizeLimit, message.count > limit {
      log.warning(
        .mail, "The message is \(message.count) bytes; \(email.server.host) takes \(limit) at most")
      let overhead = Int64(message.count) - Base64Size.encoded(fileBytes)
      throw .tooLarge(
        bytes: fileBytes, limit: Base64Size.largestInput(fitting: Int64(limit) - overhead))
    }
    try await smtp { () async throws(SMTPError) in
      try await session.authenticate(username: email.senderAddress, password: password)
    }
    try await smtp { () async throws(SMTPError) in
      try await session.send(
        message, from: email.senderAddress, to: [recipient.rawValue], progress: progress)
    }
  }

  private func smtp(_ step: () async throws(SMTPError) -> Void) async throws(SendFailure) {
    do {
      try await step()
    } catch .cancelled {
      log.info(.mail, "SMTP cancelled")
      throw .cancelled
    } catch {
      log.error(.mail, "SMTP stopped: \(error.logDescription)")
      throw SendFailure(error, provider: email.provider, host: email.server.host)
    }
  }

  /// Amazon's limit counts the file, so it is checked before connecting.
  private static func contents(of url: URL) throws(SendFailure) -> Data {
    let size: Int
    do {
      size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    } catch {
      throw .missing
    }
    if Int64(size) > FormatPolicy.emailSizeLimit {
      throw .tooLarge(bytes: Int64(size), limit: FormatPolicy.emailSizeLimit)
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw .localStorage(error.localizedDescription)
    }
  }
}

extension EmailDeliveryChannel: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// Every textual form leaves out the password, so logs and test failures can't leak it.
  public var description: String {
    "EmailDeliveryChannel(email: \(email), recipient: \(recipient), password: <redacted>)"
  }

  public var debugDescription: String { description }

  public var customMirror: Mirror {
    Mirror(self, children: ["email": email, "recipient": recipient, "password": "<redacted>"])
  }
}

/// Base64 wrapped at 76 columns, each line ending in CRLF, as `MIMEMessage` writes it.
enum Base64Size {
  static func encoded(_ bytes: Int64) -> Int64 {
    let characters = (bytes + 2) / 3 * 4
    return characters + (characters + 75) / 76 * 2
  }

  /// The most bytes whose encoding fits in `budget`: every 57 bytes make a 78-byte line.
  static func largestInput(fitting budget: Int64) -> Int64 {
    guard budget > 0 else { return 0 }
    let rest = budget % 78
    return budget / 78 * 57 + (rest >= 6 ? (rest - 2) / 4 * 3 : 0)
  }
}
