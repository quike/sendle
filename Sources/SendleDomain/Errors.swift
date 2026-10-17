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
