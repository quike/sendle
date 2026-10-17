/// Where in the conversation something went wrong.
public enum SMTPStage: String, Hashable, Sendable, CaseIterable {
  case greeting
  case hello
  case startTLS
  case authentication
  case sender
  case recipient
  case data
  /// Writing the message itself.
  case message
  /// Waiting for the server's answer to the end of the message.
  case endOfMessage
}

/// How a transport fails, before the session knows which stage it was in.
public enum SMTPTransportError: Error, Hashable, Sendable {
  case failed(String)
  case timedOut
  case closed
  case malformedReply
  /// TLS failed: the server's certificate didn't check out, or it doesn't speak TLS on this port.
  case untrusted(String)
  case cancelled
}

public enum SMTPError: Error, Hashable, Sendable {
  case connection(String, stage: SMTPStage)
  case timedOut(SMTPStage)
  /// The server answered with a code the conversation can't go on from.
  case reply(SMTPReply, stage: SMTPStage)
  case malformedReply(SMTPStage)
  /// The server offers no STARTTLS, so the password would travel in the clear.
  case tlsUnavailable
  /// The server offers neither AUTH PLAIN nor AUTH LOGIN.
  case authenticationUnavailable
  /// An address with spaces, control characters or angle brackets, which could smuggle in a
  /// command.
  case invalidAddress
  case untrustedServer(String)
  case cancelled

  public init(_ failure: SMTPTransportError, at stage: SMTPStage) {
    switch failure {
    case .failed(let detail): self = .connection(detail, stage: stage)
    case .timedOut: self = .timedOut(stage)
    case .closed: self = .connection("The server closed the connection", stage: stage)
    case .malformedReply: self = .malformedReply(stage)
    case .untrusted(let detail):
      // After the handshake, a TLS-coded error is a dropped connection, not a bad certificate.
      switch stage {
      case .greeting, .hello, .startTLS: self = .untrustedServer(detail)
      default: self = .connection(detail, stage: stage)
      }
    case .cancelled: self = .cancelled
    }
  }

  /// The whole message was sent but no answer came back, so the server may have taken it.
  public var mayHaveDeliveredMessage: Bool {
    switch self {
    case .connection(_, .endOfMessage), .timedOut(.endOfMessage), .malformedReply(.endOfMessage):
      true
    default:
      false
    }
  }
}
