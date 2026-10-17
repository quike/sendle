import Foundation

public struct SMTPTimeouts: Hashable, Sendable {
  /// Each command, its reply, and each chunk of the message.
  public var step: Duration
  /// The reply to the end of the message, which servers send after scanning it.
  public var endOfMessage: Duration

  public init(step: Duration, endOfMessage: Duration) {
    self.step = step
    self.endOfMessage = endOfMessage
  }

  public static let standard = SMTPTimeouts(step: .seconds(30), endOfMessage: .seconds(120))
}

/// One conversation with a mail server (RFC 5321): connect, sign in, send, quit.
public actor SMTPSession {
  public private(set) var capabilities = SMTPCapabilities()

  private let transport: any SMTPTransport
  private let startTLS: Bool
  private let clientName: String
  private let timeouts: SMTPTimeouts
  private var isSecure = false

  /// `clientName` is what EHLO announces; an address literal is valid for any Mac.
  public init(
    transport: any SMTPTransport,
    startTLS: Bool,
    clientName: String = "[127.0.0.1]",
    timeouts: SMTPTimeouts = .standard
  ) {
    self.transport = transport
    self.startTLS = startTLS
    self.clientName = clientName
    self.timeouts = timeouts
  }

  /// The greeting and EHLO, then STARTTLS and EHLO again when the session was made for it.
  public func connect() async throws(SMTPError) {
    try await run(.greeting) { () throws(SMTPTransportError) in try await transport.open() }
    try await expect([220], at: .greeting)
    try await hello()
    guard startTLS else { return }
    guard capabilities.startTLS else { throw .tlsUnavailable }
    try await command("STARTTLS", expecting: [220], at: .startTLS)
    try await run(.startTLS) { () throws(SMTPTransportError) in try await transport.upgradeToTLS() }
    isSecure = true
    try await hello()
  }

  /// AUTH PLAIN, or AUTH LOGIN when that is all the server offers.
  public func authenticate(username: String, password: String) async throws(SMTPError) {
    guard isSecure || !startTLS else { throw .tlsUnavailable }
    if capabilities.authMechanisms.contains("PLAIN") {
      let token = Data("\0\(username)\0\(password)".utf8).base64EncodedString()
      try await command("AUTH PLAIN \(token)", expecting: [235], at: .authentication)
    } else if capabilities.authMechanisms.contains("LOGIN") {
      try await command("AUTH LOGIN", expecting: [334], at: .authentication)
      try await command(Self.base64(username), expecting: [334], at: .authentication)
      try await command(Self.base64(password), expecting: [235], at: .authentication)
    } else {
      throw .authenticationUnavailable
    }
  }

  /// Sends `message` (CRLF lines, without the end marker), reporting progress as it is written.
  public func send(
    _ message: Data,
    from sender: String,
    to recipients: [String],
    progress: @Sendable (Double) async -> Void
  ) async throws(SMTPError) {
    guard ([sender] + recipients).allSatisfy(Self.isSafe) else { throw .invalidAddress }
    let size = capabilities.sizeLimit == nil ? "" : " SIZE=\(message.count)"
    try await command("MAIL FROM:<\(sender)>\(size)", expecting: [250], at: .sender)
    for recipient in recipients {
      try await command("RCPT TO:<\(recipient)>", expecting: [250, 251], at: .recipient)
    }
    try await command("DATA", expecting: [354], at: .data)
    let data = MessageData.terminated(message)
    // About a hundred writes: progress moves in 1% steps without a call per line.
    let chunk = max(16_384, data.count / 100)
    await progress(0)
    var offset = 0
    while offset < data.count {
      if Task.isCancelled { throw .cancelled }
      let end = min(offset + chunk, data.count)
      let part = data.subdata(in: offset..<end)
      // The last chunk carries the end marker, so a failure after it may still have delivered.
      let stage: SMTPStage = end == data.count ? .endOfMessage : .message
      try await run(stage) { () throws(SMTPTransportError) in
        try await transport.write(part, timeout: timeouts.step)
      }
      offset = end
      await progress(Double(offset) / Double(data.count))
    }
    try await expect([250], at: .endOfMessage, timeout: timeouts.endOfMessage)
  }

  /// Says goodbye and closes the connection; a failure here changes nothing. The goodbye gets
  /// five seconds, since it holds up the next book and decides nothing.
  public func quit() async {
    let timeout = Duration.seconds(5)
    do {
      try await transport.write(Data("QUIT\r\n".utf8), timeout: timeout)
      _ = try await transport.readReply(timeout: timeout)
    } catch {}
    await transport.close()
  }

  /// Drops the connection without a goodbye, for when it may be stuck.
  public func close() async {
    await transport.close()
  }

  // MARK: Private

  private func hello() async throws(SMTPError) {
    let reply = try await command("EHLO \(clientName)", expecting: [250], at: .hello)
    capabilities = SMTPCapabilities(ehlo: reply)
  }

  @discardableResult
  private func command(
    _ line: String,
    expecting codes: Set<Int>,
    at stage: SMTPStage
  ) async throws(SMTPError) -> SMTPReply {
    if Task.isCancelled { throw Self.cancellation(at: stage) }
    try await run(stage) { () throws(SMTPTransportError) in
      try await transport.write(Data((line + "\r\n").utf8), timeout: timeouts.step)
    }
    return try await expect(codes, at: stage)
  }

  @discardableResult
  private func expect(
    _ codes: Set<Int>,
    at stage: SMTPStage,
    timeout: Duration? = nil
  ) async throws(SMTPError) -> SMTPReply {
    if Task.isCancelled { throw Self.cancellation(at: stage) }
    let reply = try await run(stage) { () throws(SMTPTransportError) in
      try await transport.readReply(timeout: timeout ?? timeouts.step)
    }
    guard codes.contains(reply.code) else { throw .reply(reply, stage: stage) }
    return reply
  }

  private func run<T>(
    _ stage: SMTPStage,
    _ operation: () async throws(SMTPTransportError) -> T
  ) async throws(SMTPError) -> T {
    do {
      return try await operation()
    } catch {
      throw Task.isCancelled ? Self.cancellation(at: stage) : SMTPError(error, at: stage)
    }
  }

  /// Once the end marker may have reached the server, a cancel must not claim nothing was sent.
  private static func cancellation(at stage: SMTPStage) -> SMTPError {
    stage == .endOfMessage
      ? .connection("Cancelled before the server answered", stage: .endOfMessage) : .cancelled
  }

  private static func isSafe(_ address: String) -> Bool {
    !address.isEmpty && !address.contains { $0.isWhitespace || $0 == "<" || $0 == ">" }
      && !address.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
  }

  private static func base64(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
  }
}
