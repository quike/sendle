import Foundation
import SMTPKit
import Testing

struct MIMEMessageTests {
  let epub = Data((0..<1_000).map { UInt8($0 % 251) })

  func message(
    subject: String = "Moby-Dick - Herman Melville",
    text: String = "Sent by Sendle.",
    filename: String = "Moby-Dick - Herman Melville.epub"
  ) -> MIMEMessage {
    MIMEMessage(
      from: "me@gmail.com", to: "reader@kindle.com", subject: subject, text: text,
      attachment: MIMEMessage.Attachment(
        filename: filename, contentType: "application/epub+zip", data: epub),
      date: Date(timeIntervalSince1970: 1_792_159_500), messageID: "<id-1@gmail.com>",
      boundary: "=_Sendle_b1")
  }

  func text(_ message: MIMEMessage) -> String {
    String(decoding: message.encoded(), as: UTF8.self)
  }

  /// The lines between a part's blank line and the next boundary.
  func body(ofPart index: Int, in text: String) -> [String] {
    let part = text.components(separatedBy: "--=_Sendle_b1\r\n")[index]
    let content = part.components(separatedBy: "\r\n\r\n")[1]
    return content.components(separatedBy: "\r\n").filter { !$0.isEmpty && !$0.hasPrefix("--") }
  }

  func decodedWords(_ header: String) -> String {
    let words = header.matches(of: /=\?UTF-8\?B\?([A-Za-z0-9+\/=]*)\?=/).map { String($0.1) }
    return words.map { String(decoding: Data(base64Encoded: $0) ?? Data(), as: UTF8.self) }
      .joined()
  }

  func subjectHeader(_ text: String) -> String {
    let lines = text.components(separatedBy: "\r\n")
    let start = lines.firstIndex { $0.hasPrefix("Subject: ") } ?? 0
    let folded = lines[(start + 1)...].prefix { $0.hasPrefix(" ") }
    return ([lines[start]] + folded).joined(separator: "\r\n")
  }

  @Test func writesTheHeadersMailServersExpect() {
    let head = text(message()).components(separatedBy: "\r\n\r\n")[0]

    #expect(
      head == """
        From: me@gmail.com\r
        To: reader@kindle.com\r
        Subject: Moby-Dick - Herman Melville\r
        Date: Fri, 16 Oct 2026 14:05:00 +0000\r
        Message-ID: <id-1@gmail.com>\r
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed;\r
         boundary="=_Sendle_b1"
        """)
  }

  @Test func encodesANonASCIISubjectInUTF8Words() {
    let header = subjectHeader(text(message(subject: "Café — Zoë")))

    #expect(header.hasPrefix("Subject: =?UTF-8?B?"))
    #expect(decodedWords(header) == "Café — Zoë")
  }

  @Test func foldsALongSubjectWithoutSplittingACharacter() {
    let subject = String(repeating: "Ünïcödé títle ", count: 12)

    let header = subjectHeader(text(message(subject: subject)))

    let lines = header.components(separatedBy: "\r\n")
    #expect(lines.count > 1)
    #expect(lines.allSatisfy { $0.count <= 76 })
    #expect(decodedWords(header) == subject)
    for word in header.matches(of: /\?B\?([^?]*)\?=/) {
      #expect(String(data: Data(base64Encoded: String(word.1)) ?? Data(), encoding: .utf8) != nil)
    }
  }

  @Test func keepsALongPlainSubjectUnderTheLineLimit() {
    let header = subjectHeader(text(message(subject: String(repeating: "Long title ", count: 10))))

    #expect(header.components(separatedBy: "\r\n").allSatisfy { $0.count <= 76 })
    #expect(decodedWords(header) == String(repeating: "Long title ", count: 10))
  }

  @Test func namesAPlainAttachmentInQuotes() {
    let encoded = text(message())

    #expect(
      encoded.contains(
        "Content-Type: application/epub+zip;\r\n name=\"Moby-Dick - Herman Melville.epub\""))
    #expect(
      encoded.contains(
        "Content-Disposition: attachment;\r\n filename=\"Moby-Dick - Herman Melville.epub\""))
  }

  @Test func namesAnAttachmentWithOtherCharactersPerRFC2231() {
    let encoded = text(message(filename: "Café \"Noir\".epub"))

    #expect(encoded.contains(" filename*=UTF-8''Caf%C3%A9%20%22Noir%22.epub"))
    #expect(encoded.contains(" name*=UTF-8''Caf%C3%A9%20%22Noir%22.epub"))
  }

  @Test func wrapsTheAttachmentAt76Columns() {
    let lines = body(ofPart: 2, in: text(message()))

    #expect(lines.dropLast().allSatisfy { $0.count == 76 })
    #expect(Data(base64Encoded: lines.joined()) == epub)
  }

  @Test func sendsPlainTextAsIs() {
    #expect(
      body(ofPart: 1, in: text(message(text: "Sent by Sendle.\nEnjoy."))) == [
        "Sent by Sendle.", "Enjoy.",
      ])
  }

  @Test func sendsOtherTextInBase64() {
    let encoded = text(message(text: "Envoyé par Sendle."))

    #expect(
      encoded.contains("Content-Transfer-Encoding: base64\r\n\r\nRW52b3nDqSBwYXIgU2VuZGxlLg=="))
  }

  @Test func endsEveryLineWithCRLFAndClosesTheParts() {
    let encoded = message(text: "one\ntwo\rthree").encoded()
    let bytes = Array(encoded)

    for (index, byte) in bytes.enumerated() where byte == 0x0A {
      #expect(index > 0 && bytes[index - 1] == 0x0D)
    }
    for (index, byte) in bytes.enumerated() where byte == 0x0D {
      #expect(index + 1 < bytes.count && bytes[index + 1] == 0x0A)
    }
    #expect(String(decoding: encoded, as: UTF8.self).hasSuffix("\r\n--=_Sendle_b1--\r\n"))
  }

  @Test func makesAFreshIDAndBoundaryForEachMessage() {
    let attachment = MIMEMessage.Attachment(
      filename: "a.txt", contentType: "text/plain", data: Data())
    let first = MIMEMessage(
      from: "me@gmail.com", to: "k@kindle.com", subject: "a", text: "", attachment: attachment)
    let second = MIMEMessage(
      from: "me@gmail.com", to: "k@kindle.com", subject: "a", text: "", attachment: attachment)

    #expect(first.messageID != second.messageID)
    #expect(first.boundary != second.boundary)
    #expect(first.messageID.hasSuffix("@gmail.com>"))
  }
}
