public enum SMTPSecurity: String, Sendable, Codable {
  case implicitTLS
  case startTLS
}

public struct SMTPServer: Hashable, Sendable, Codable {
  public let host: String
  public let port: Int
  public let security: SMTPSecurity

  public init(host: String, port: Int, security: SMTPSecurity) {
    self.host = host
    self.port = port
    self.security = security
  }

  public var isValid: Bool { !host.isEmpty && (1...65_535).contains(port) }
}

public enum MailProvider: String, Sendable, Codable, CaseIterable {
  case gmail
  case iCloud
  case fastmail
  case custom

  /// Server settings each provider documents for app-password SMTP.
  public var defaultServer: SMTPServer? {
    switch self {
    case .gmail: SMTPServer(host: "smtp.gmail.com", port: 465, security: .implicitTLS)
    case .iCloud: SMTPServer(host: "smtp.mail.me.com", port: 587, security: .startTLS)
    case .fastmail: SMTPServer(host: "smtp.fastmail.com", port: 465, security: .implicitTLS)
    case .custom: nil
    }
  }
}

public struct EmailSettings: Hashable, Sendable, Codable {
  public let kindleAddress: KindleEmail
  public let senderAddress: String
  public let provider: MailProvider
  public let server: SMTPServer

  public init(
    kindleAddress: KindleEmail,
    senderAddress: String,
    provider: MailProvider,
    server: SMTPServer
  ) {
    self.kindleAddress = kindleAddress
    self.senderAddress = senderAddress
    self.provider = provider
    self.server = server
  }
}
