public enum LibraryError: Error, Hashable, Sendable {
  case accessDenied
  case notFound
  case unsupportedSchema(missingColumns: [String])
  case unreadable(String)
}

public enum SendFailure: Error, Hashable, Sendable {
  case authenticationFailed(MailProvider)
  /// Only for failures before the server accepted the message: SendBooks retries it once.
  case connectionFailed(host: String)
  /// The connection broke after the whole message was sent: the server may have accepted it.
  case unconfirmed(host: String)
  case rejected(String)
  /// Sendle won't send through the mail account as it is set up, for example without TLS.
  case mailSetup(String)
  case notConfigured
  /// The sender's app password is missing from the Keychain, or the Keychain refused to give it.
  case passwordUnavailable
  case tooLarge(bytes: Int64, limit: Int64)
  case protected
  case inCloudOnly
  case missing
  case invalidBook(String)
  case conversionUnavailable
  case conversionFailed(String)
  case deviceDisconnected
  case diskFull
  /// Writing to the Kindle failed while it stayed plugged in.
  case copyFailed(String)
  case localStorage(String)
  case cancelled

  /// Only transient network problems are worth a second attempt.
  public var isRetryable: Bool {
    if case .connectionFailed = self { return true }
    return false
  }
}

public enum StorageError: Error, Hashable, Sendable {
  case writeFailed(String)
  case keychain(status: Int32)
}

extension LibraryError {
  /// A few words for the logs.
  public var logDescription: String {
    switch self {
    case .accessDenied: "Sendle has no Full Disk Access"
    case .notFound: "there is no Books library on this Mac"
    case .unsupportedSchema(let columns):
      "this version of Books lacks \(columns.joined(separator: ", "))"
    case .unreadable(let detail): detail
    }
  }
}

extension SendFailure {
  /// A few words for the logs; the panel's wording comes from `ProblemPresenter`.
  public var logDescription: String {
    switch self {
    case .authenticationFailed: "the mail server didn't accept the password"
    case .connectionFailed(let host): "couldn't reach \(host)"
    case .unconfirmed(let host): "\(host) didn't confirm the message, which may still arrive"
    case .rejected(let detail): "the mail server refused it: \(detail)"
    case .mailSetup(let detail): "the sender settings need a look: \(detail)"
    case .notConfigured: "the Kindle email isn't set up"
    case .passwordUnavailable: "there's no app password to sign in with"
    case .tooLarge(let bytes, let limit):
      "\(ByteCount.text(bytes)) is over the \(ByteCount.text(limit)) limit"
    case .protected: "protected by DRM"
    case .inCloudOnly: "only in iCloud"
    case .missing: "the book's file is gone"
    case .invalidBook(let detail): "the EPUB is damaged: \(detail)"
    case .conversionUnavailable: "boko isn't installed"
    case .conversionFailed(let detail): "boko couldn't convert it: \(detail)"
    case .deviceDisconnected: "the Kindle was unplugged"
    case .diskFull: "the Kindle is full"
    case .copyFailed(let detail): "the copy failed: \(detail)"
    case .localStorage(let detail): "couldn't write temporary files: \(detail)"
    case .cancelled: "cancelled"
    }
  }
}
