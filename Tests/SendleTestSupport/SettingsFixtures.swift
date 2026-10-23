import SendleDomain

extension EmailSettings {
  public static let fixture = EmailSettings(
    kindleAddress: .fixture,
    senderAddress: "me@gmail.com",
    provider: .gmail,
    server: SMTPServer(host: "smtp.gmail.com", port: 465, security: .implicitTLS)
  )
}
