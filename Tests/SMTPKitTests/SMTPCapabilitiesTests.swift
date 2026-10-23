import SMTPKit
import Testing

struct SMTPCapabilitiesTests {
  func ehlo(_ keywords: String...) -> SMTPReply {
    SMTPReply(code: 250, lines: ["outbound.mr.icloud.com"] + keywords)
  }

  @Test func readsWhatICloudOffersBeforeTLS() {
    let capabilities = SMTPCapabilities(
      ehlo: ehlo("PIPELINING", "SIZE 28319744", "STARTTLS", "8BITMIME", "SMTPUTF8"))

    #expect(capabilities == SMTPCapabilities(sizeLimit: 28_319_744, startTLS: true))
  }

  @Test func readsThePasswordMechanismsOfferedAfterTLS() {
    let capabilities = SMTPCapabilities(
      ehlo: ehlo("SIZE 28319744", "AUTH LOGIN PLAIN ATOKEN XOAUTH2"))

    #expect(capabilities.authMechanisms == ["LOGIN", "PLAIN", "ATOKEN", "XOAUTH2"])
    #expect(!capabilities.startTLS)
  }

  @Test func readsTheOldAuthEqualsForm() {
    #expect(SMTPCapabilities(ehlo: ehlo("auth=login plain")).authMechanisms == ["LOGIN", "PLAIN"])
  }

  @Test(arguments: ["SIZE", "SIZE 0", "SIZE lots"])
  func treatsASizeWithoutALimitAsNone(keyword: String) {
    #expect(SMTPCapabilities(ehlo: ehlo(keyword)).sizeLimit == nil)
  }

  @Test func ignoresTheGreetingLine() {
    let reply = SMTPReply(code: 250, lines: ["STARTTLS.example.com"])

    #expect(SMTPCapabilities(ehlo: reply) == SMTPCapabilities())
  }
}
