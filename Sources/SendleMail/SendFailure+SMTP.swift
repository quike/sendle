import SMTPKit
import SendleDomain

extension SendFailure {
  /// `.connectionFailed`, which SendBooks retries, only when the server certainly kept nothing.
  /// Sign-in replies become their code alone: a server may echo the credentials.
  init(_ error: SMTPError, provider: MailProvider, host: String) {
    switch error {
    case .reply(let reply, _) where reply.code == 534 || reply.code == 535:
      self = .authenticationFailed(provider)
    case .reply(let reply, _) where (400..<500).contains(reply.code):
      self = .connectionFailed(host: host)
    case .reply(let reply, .authentication):
      self = .mailSetup("The server refused the sign-in (\(reply.code)).")
    case .reply(let reply, _):
      self = .rejected(reply.description)
    case .tlsUnavailable:
      self = .mailSetup(
        "\(host) doesn't offer a secure connection, so Sendle didn't send your password.")
    case .authenticationUnavailable:
      self = .mailSetup("\(host) doesn't accept an app password.")
    case .invalidAddress:
      self = .mailSetup("The sender or Kindle address can't be used.")
    case .untrustedServer:
      self = .mailSetup(
        "Sendle couldn't confirm it was talking to \(host), so it didn't connect. "
          + "Check the server and its security.")
    case .cancelled:
      self = .cancelled
    case _ where error.mayHaveDeliveredMessage:
      self = .unconfirmed(host: host)
    case .connection, .timedOut, .malformedReply:
      self = .connectionFailed(host: host)
    }
  }
}

extension SMTPError {
  /// Keeps only the code of a sign-in reply, as `SendFailure.init` does.
  package var logDescription: String {
    switch self {
    case .connection(let detail, let stage): "connection failed at \(stage.rawValue): \(detail)"
    case .timedOut(let stage): "no answer in time at \(stage.rawValue)"
    case .reply(let reply, .authentication): "reply \(reply.code) at authentication"
    case .reply(let reply, let stage): "reply \(reply) at \(stage.rawValue)"
    case .malformedReply(let stage): "unreadable reply at \(stage.rawValue)"
    case .tlsUnavailable: "the server offers no STARTTLS"
    case .authenticationUnavailable: "the server offers neither AUTH PLAIN nor AUTH LOGIN"
    case .invalidAddress: "an address has spaces, control characters or angle brackets"
    case .untrustedServer(let detail): "TLS failed: \(detail)"
    case .cancelled: "cancelled"
    }
  }
}
