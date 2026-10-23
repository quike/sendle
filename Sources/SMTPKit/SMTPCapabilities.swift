/// What a server offers in its EHLO reply.
public struct SMTPCapabilities: Hashable, Sendable {
  /// The largest message the server takes, in bytes (RFC 1870); nil when it names no limit.
  public let sizeLimit: Int?
  /// Upper-cased SASL mechanism names, such as PLAIN and LOGIN.
  public let authMechanisms: Set<String>
  public let startTLS: Bool

  public init(sizeLimit: Int? = nil, authMechanisms: Set<String> = [], startTLS: Bool = false) {
    self.sizeLimit = sizeLimit
    self.authMechanisms = authMechanisms
    self.startTLS = startTLS
  }

  /// The first line of an EHLO reply greets; each line after it names one extension.
  public init(ehlo reply: SMTPReply) {
    var sizeLimit: Int?
    var mechanisms: Set<String> = []
    var startTLS = false
    for line in reply.lines.dropFirst() {
      let words = line.split(whereSeparator: \.isWhitespace).map { $0.uppercased() }
      guard let keyword = words.first else { continue }
      switch keyword {
      case "SIZE":
        sizeLimit = words.dropFirst().first.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
      case "STARTTLS":
        startTLS = true
      case "AUTH":
        mechanisms.formUnion(words.dropFirst())
      case _ where keyword.hasPrefix("AUTH="):
        mechanisms.insert(String(keyword.dropFirst(5)))
        mechanisms.formUnion(words.dropFirst())
      default:
        continue
      }
    }
    self.init(sizeLimit: sizeLimit, authMechanisms: mechanisms, startTLS: startTLS)
  }
}
