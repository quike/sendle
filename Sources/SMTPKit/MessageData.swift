import Foundation

package enum MessageData {
  /// The message as DATA sends it: a line that starts with "." gets a second one, and the end
  /// marker follows (RFC 5321 §4.5.2). Lines must already end in CRLF, as `MIMEMessage` writes
  /// them.
  package static func terminated(_ message: Data) -> Data {
    let dot = UInt8(ascii: ".")
    var result = Data(capacity: message.count + message.count / 1_000 + 5)
    var atLineStart = true
    for byte in message {
      if atLineStart, byte == dot { result.append(dot) }
      result.append(byte)
      atLineStart = byte == UInt8(ascii: "\n")
    }
    if !result.isEmpty, !result.ends(with: Data("\r\n".utf8)) {
      result.append(contentsOf: Array("\r\n".utf8))
    }
    result.append(contentsOf: Array(".\r\n".utf8))
    return result
  }
}

extension Data {
  fileprivate func ends(with suffix: Data) -> Bool {
    count >= suffix.count && self[index(endIndex, offsetBy: -suffix.count)...] == suffix
  }
}
