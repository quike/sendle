import Foundation

/// A TCP connection through `URLSessionStreamTask`, which also does the TLS: before the greeting
/// for implicit TLS, or after STARTTLS.
public actor StreamTaskTransport: SMTPTransport {
  private let session = URLSession(configuration: .ephemeral)
  private let task: URLSessionStreamTask
  private let implicitTLS: Bool
  private var parser = ReplyParser()

  public init(host: String, port: Int, implicitTLS: Bool) {
    task = session.streamTask(withHostName: host, port: port)
    self.implicitTLS = implicitTLS
  }

  deinit {
    session.invalidateAndCancel()
  }

  public func open() async throws(SMTPTransportError) {
    if implicitTLS { task.startSecureConnection() }
    task.resume()
  }

  public func readReply(timeout: Duration) async throws(SMTPTransportError) -> SMTPReply {
    let task = task
    while true {
      if let reply = try parser.nextReply() { return reply }
      let (data, atEnd) = try await perform {
        try await task.readData(ofMinLength: 1, maxLength: 65_536, timeout: timeout.seconds)
      }
      if let data { parser.append(data) }
      if atEnd, data?.isEmpty ?? true { throw .closed }
    }
  }

  public func write(_ data: Data, timeout: Duration) async throws(SMTPTransportError) {
    let task = task
    try await perform { try await task.write(data, timeout: timeout.seconds) }
  }

  /// Plain-text bytes that arrived before the upgrade are dropped, as RFC 3207 §4.2 requires.
  public func upgradeToTLS() async throws(SMTPTransportError) {
    parser.reset()
    task.startSecureConnection()
  }

  public func close() async {
    task.cancel()
    session.invalidateAndCancel()
  }

  /// The stream task ignores Swift cancellation, so cancelling cancels the task too; a cancelled
  /// read then returns instead of throwing.
  private func perform<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async throws(SMTPTransportError) -> T {
    let task = task
    let result: T
    do {
      result = try await withTaskCancellationHandler(operation: operation) { task.cancel() }
    } catch {
      throw Task.isCancelled ? .cancelled : Self.failure(error)
    }
    if Task.isCancelled { throw .cancelled }
    return result
  }

  private static func failure(_ error: any Error) -> SMTPTransportError {
    let error = error as NSError
    switch (error.domain, error.code) {
    case (NSPOSIXErrorDomain, Int(ETIMEDOUT)), (NSURLErrorDomain, NSURLErrorTimedOut):
      return .timedOut
    // Secure Transport's errSSL codes, and URL loading's certificate errors.
    case (NSOSStatusErrorDomain, -9899...(-9800)),
      (NSURLErrorDomain, NSURLErrorClientCertificateRequired...NSURLErrorSecureConnectionFailed):
      return .untrusted("\(error.domain) \(error.code): \(error.localizedDescription)")
    default: return .failed("\(error.domain) \(error.code): \(error.localizedDescription)")
    }
  }
}

extension Duration {
  fileprivate var seconds: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
  }
}
