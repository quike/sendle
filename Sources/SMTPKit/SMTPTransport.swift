import Foundation

/// A connection to a mail server, which `SMTPSession` drives one call at a time.
public protocol SMTPTransport: Sendable {
  /// Connects; with implicit TLS the handshake comes first.
  func open() async throws(SMTPTransportError)
  func readReply(timeout: Duration) async throws(SMTPTransportError) -> SMTPReply
  func write(_ data: Data, timeout: Duration) async throws(SMTPTransportError)
  /// Switches the open connection to TLS, after the server's 220 to STARTTLS.
  func upgradeToTLS() async throws(SMTPTransportError)
  func close() async
}
