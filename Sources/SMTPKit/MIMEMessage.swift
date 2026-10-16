import Foundation

/// A text part and one attachment, encoded with 7-bit-safe headers and CRLF line ends.
public struct MIMEMessage: Sendable {
  public struct Attachment: Sendable {
    public let filename: String
    public let contentType: String
    public let data: Data

    public init(filename: String, contentType: String, data: Data) {
      self.filename = filename
      self.contentType = contentType
      self.data = data
    }
  }

  public let from: String
  public let to: String
  public let subject: String
  public let text: String
  public let attachment: Attachment
  public let date: Date
  public let messageID: String
  public let boundary: String

  public init(
    from: String,
    to: String,
    subject: String,
    text: String,
    attachment: Attachment,
    date: Date = Date(),
    messageID: String? = nil,
    boundary: String? = nil
  ) {
    self.from = from
    self.to = to
    self.subject = subject
    self.text = text
    self.attachment = attachment
    self.date = date
    let domain = from.split(separator: "@").last.map(String.init) ?? "sendle.local"
    self.messageID = messageID ?? "<\(UUID().uuidString)@\(domain)>"
    // "=_" can't occur in base64 or in a 7-bit text part that doesn't contain it already.
    self.boundary =
      boundary ?? "=_Sendle_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
  }

  public func encoded() -> Data {
    let text = Self.crlf(self.text)
    let textIsPlain = text.unicodeScalars.allSatisfy { $0.isASCII }
    let lines = [
      "From: \(from)",
      "To: \(to)",
      Self.subjectHeader(subject),
      "Date: \(Self.dateFormat.format(date))",
      "Message-ID: \(messageID)",
      "MIME-Version: 1.0",
      "Content-Type: multipart/mixed;\r\n boundary=\"\(boundary)\"",
      "",
      "--\(boundary)",
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: \(textIsPlain ? "7bit" : "base64")",
      "",
      textIsPlain ? text : Self.base64(Data(text.utf8)),
      "--\(boundary)",
      "Content-Type: \(attachment.contentType);\r\n \(Self.parameter("name", attachment.filename))",
      "Content-Disposition: attachment;\r\n \(Self.parameter("filename", attachment.filename))",
      "Content-Transfer-Encoding: base64",
      "",
      Self.base64(attachment.data),
      "--\(boundary)--",
      "",
    ]
    return Data(lines.joined(separator: "\r\n").utf8)
  }

  // MARK: Encoding

  private static let dateFormat = Date.VerbatimFormatStyle(
    format: """
      \(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \
      \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
      \(second: .twoDigits) +0000
      """,
    locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt,
    calendar: Calendar(identifier: .gregorian))

  /// Short printable ASCII stays readable; anything else becomes RFC 2047 encoded words, one per
  /// folded line, each holding whole characters.
  private static func subjectHeader(_ subject: String) -> String {
    let isPlain = subject.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    if isPlain, !subject.contains("=?"), "Subject: ".count + subject.count <= 76 {
      return "Subject: \(subject)"
    }
    // 39 bytes make 52 base64 characters, so every line stays within RFC 2047's 76.
    var words: [String] = []
    var chunk = Data()
    for scalar in subject.unicodeScalars {
      let bytes = Data(String(scalar).utf8)
      if chunk.count + bytes.count > 39 {
        words.append("=?UTF-8?B?\(chunk.base64EncodedString())?=")
        chunk = Data()
      }
      chunk.append(bytes)
    }
    if !chunk.isEmpty || words.isEmpty {
      words.append("=?UTF-8?B?\(chunk.base64EncodedString())?=")
    }
    return "Subject: " + words.joined(separator: "\r\n ")
  }

  /// A quoted value when it is plain ASCII, otherwise RFC 2231's percent-encoded UTF-8.
  private static func parameter(_ name: String, _ value: String) -> String {
    let isPlain = value.unicodeScalars.allSatisfy {
      (0x20...0x7E).contains($0.value) && $0 != "\"" && $0 != "\\"
    }
    if isPlain { return "\(name)=\"\(value)\"" }
    let allowed = Set("!#$&+-.^_`|~".utf8)
    let encoded = value.utf8.map { byte in
      let isAlphanumeric =
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
        || (0x61...0x7A).contains(byte)
      return isAlphanumeric || allowed.contains(byte)
        ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
    }
    return "\(name)*=UTF-8''\(encoded.joined())"
  }

  private static func base64(_ data: Data) -> String {
    data.base64EncodedString(options: [
      .lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed,
    ])
  }

  private static func crlf(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\r\n")
  }
}
