public enum LibraryError: Error, Hashable, Sendable {
  case accessDenied
  case notFound
  case unsupportedSchema(missingColumns: [String])
  case unreadable(String)
}

public enum SendFailure: Error, Hashable, Sendable {
  case authenticationFailed(MailProvider)
  case connectionFailed(host: String)
  case rejected(String)
  case notConfigured
  case tooLarge(bytes: Int64, limit: Int64)
  case protected
  case inCloudOnly
  case missing
  case invalidBook(String)
  case conversionUnavailable
  case conversionFailed(String)
  case deviceDisconnected
  case diskFull
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
