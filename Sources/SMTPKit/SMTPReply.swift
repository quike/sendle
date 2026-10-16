import Foundation

/// A server reply: its three-digit code and the text of each line.
public struct SMTPReply: Hashable, Sendable, CustomStringConvertible {
  public let code: Int
  public let lines: [String]

  public init(code: Int, lines: [String]) {
    self.code = code
    self.lines = lines
  }

  public var text: String { lines.joined(separator: " ") }
  public var description: String { "\(code) \(text)" }
}

/// Splits the bytes a server sends into replies (RFC 5321 §4.2).
package struct ReplyParser: Sendable {
  /// RFC 5321 allows 512 bytes per reply line; anything far longer is not a mail server.
  package static let maxLineLength = 4_096
  package static let maxLines = 512

  private var buffer = Data()
  private var code: Int?
  private var lines: [String] = []

  package init() {}

  package mutating func append(_ data: Data) {
    buffer.append(data)
  }

  /// The next complete reply, or nil until more bytes arrive.
  package mutating func nextReply() throws(SMTPTransportError) -> SMTPReply? {
    while let newline = buffer.firstIndex(of: 0x0A) {
      var line = buffer[buffer.startIndex..<newline]
      buffer = Data(buffer[buffer.index(after: newline)...])
      if line.last == 0x0D { line = line.dropLast() }
      guard line.count <= Self.maxLineLength, lines.count < Self.maxLines else {
        throw .malformedReply
      }
      if let reply = try take(Array(line)) { return reply }
    }
    guard buffer.count <= Self.maxLineLength else { throw .malformedReply }
    return nil
  }

  /// Forgets everything received so far, as the client must after STARTTLS (RFC 3207 §4.2).
  package mutating func reset() {
    self = ReplyParser()
  }

  private mutating func take(_ line: [UInt8]) throws(SMTPTransportError) -> SMTPReply? {
    let digits = line.prefix(3)
    guard digits.count == 3, digits.allSatisfy({ (0x30...0x39).contains($0) }),
      let lineCode = Int(String(decoding: digits, as: UTF8.self)), code == nil || code == lineCode
    else { throw .malformedReply }
    let separator = line.count > 3 ? line[3] : UInt8(ascii: " ")
    guard separator == UInt8(ascii: " ") || separator == UInt8(ascii: "-") else {
      throw .malformedReply
    }
    code = lineCode
    lines.append(String(decoding: line.dropFirst(4), as: UTF8.self))
    guard separator == UInt8(ascii: " ") else { return nil }
    defer {
      code = nil
      lines = []
    }
    return SMTPReply(code: lineCode, lines: lines)
  }
}
