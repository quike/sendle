/// One step of the conversation with a mail server. Credentials are already hidden.
public struct SMTPTranscriptLine: Hashable, Sendable {
  public enum Direction: Hashable, Sendable {
    case client
    case server
  }

  public let direction: Direction
  /// A command, or a whole reply with one line per reply line.
  public let text: String
  /// The reply's code, for server lines.
  public let code: Int?

  public init(direction: Direction, text: String, code: Int? = nil) {
    self.direction = direction
    self.text = text
    self.code = code
  }
}

public typealias SMTPTranscript = @Sendable (SMTPTranscriptLine) -> Void

extension SMTPReply {
  /// The reply as the server wrote it: "250-…" for each line but the last, "250 …" for that.
  var transcript: String {
    lines.enumerated().map { index, line in
      "\(code)\(index == lines.count - 1 ? " " : "-")\(line)"
    }
    .joined(separator: "\n")
  }
}
