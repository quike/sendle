import SMTPKit
import SendleDomain

extension SendFailure {
  /// `.connectionFailed`, which SendBooks retries, only when the server certainly kept nothing.
  init(_ error: SMTPError, provider: MailProvider, host: String) {
    switch error {
    case .reply(let reply, _) where reply.code == 534 || reply.code == 535:
      self = .authenticationFailed(provider)
    case .reply(let reply, _) where (400..<500).contains(reply.code):
      self = .connectionFailed(host: host)
    case .reply(let reply, _):
      self = .rejected(reply.description)
    case .tlsUnavailable:
      self = .rejected(
        "\(host) doesn't offer a secure connection, so Sendle didn't send your password.")
    case .authenticationUnavailable:
      self = .rejected("\(host) doesn't accept an app password.")
    case .invalidAddress:
      self = .rejected("The sender or Kindle address can't be used.")
    case .cancelled:
      self = .cancelled
    case _ where error.mayHaveDeliveredMessage:
      self = .unconfirmed(host: host)
    case .connection, .timedOut, .malformedReply:
      self = .connectionFailed(host: host)
    }
  }
}
