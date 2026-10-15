import Foundation

public enum SendEvent: Hashable, Sendable {
  case preparing(BookID)
  case uploading(BookID, fraction: Double)
  case sent(BookID, fixes: [EPUBFix])
  case failed(BookID, SendFailure)
}

/// Sends books one at a time: plan, prepare, deliver, record, clean up.
public struct SendBooks: Sendable {
  public typealias Sleep = @Sendable (Duration) async -> Void

  private let channels: any DeliveryChannelFactory
  private let preparer: any EPUBPreparer
  private let converter: any FormatConverter
  private let staging: any StagingArea
  private let history: any SendHistoryStore
  private let now: @Sendable () -> Date
  private let retryDelay: Duration
  private let sleep: Sleep

  public init(
    channels: any DeliveryChannelFactory,
    preparer: any EPUBPreparer,
    converter: any FormatConverter,
    staging: any StagingArea,
    history: any SendHistoryStore,
    now: @escaping @Sendable () -> Date = { Date() },
    retryDelay: Duration = .seconds(2),
    sleep: @escaping Sleep = { try? await Task.sleep(for: $0) }
  ) {
    self.channels = channels
    self.preparer = preparer
    self.converter = converter
    self.staging = staging
    self.history = history
    self.now = now
    self.retryDelay = retryDelay
    self.sleep = sleep
  }

  /// Reports every step through `onEvent`, in order. Cancel the calling task to stop;
  /// books not yet sent are reported as `.cancelled`.
  public func callAsFunction(
    _ books: [Book],
    to destination: Destination,
    onEvent: @Sendable (SendEvent) async -> Void
  ) async {
    for book in books {
      if Task.isCancelled {
        await onEvent(.failed(book.id, .cancelled))
        continue
      }
      await onEvent(await send(book, to: destination, onEvent: onEvent))
    }
  }

  private func send(
    _ book: Book,
    to destination: Destination,
    onEvent: @Sendable (SendEvent) async -> Void
  ) async -> SendEvent {
    let steps: [SendStep]
    switch FormatPolicy.plan(
      for: book, to: destination.kind, converterAvailable: converter.isAvailable)
    {
    case .blocked(let reason, _): return .failed(book.id, reason)
    case .send(let planned): steps = planned
    }
    await onEvent(.preparing(book.id))
    do throws(SendFailure) {
      let directory = try staging.makeDirectory()
      defer { staging.remove(directory) }
      let file = try await run(steps, for: book, to: destination, in: directory, onEvent: onEvent)
      await record(book, to: destination, .sent)
      return .sent(book.id, fixes: file.fixes)
    } catch {
      let failure = Task.isCancelled ? .cancelled : error
      if failure != .cancelled {
        await record(book, to: destination, .failed)
      }
      return .failed(book.id, failure)
    }
  }

  private func run(
    _ steps: [SendStep],
    for book: Book,
    to destination: Destination,
    in directory: URL,
    onEvent: @Sendable (SendEvent) async -> Void
  ) async throws(SendFailure) -> PreparedFile {
    var file = PreparedFile(url: book.fileURL, format: book.format.fileFormat)
    for step in steps {
      if Task.isCancelled { throw .cancelled }
      switch step {
      case .prepareEPUB:
        file = try await preparer.prepare(book, in: directory)
      case .convert(let format):
        let converted = try await converter.convert(file, to: format, in: directory)
        file = PreparedFile(url: converted.url, format: converted.format, fixes: file.fixes)
      case .deliver:
        let channel = try await channels.channel(for: destination)
        try await deliver(file, named: FileNaming.baseName(for: book), via: channel) { fraction in
          await onEvent(.uploading(book.id, fraction: fraction))
        }
      }
    }
    return file
  }

  private func deliver(
    _ file: PreparedFile,
    named name: String,
    via channel: any DeliveryChannel,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    do throws(SendFailure) {
      try await channel.deliver(file, named: name, progress: progress)
    } catch {
      guard error.isRetryable, !Task.isCancelled else { throw error }
      await sleep(retryDelay)
      if Task.isCancelled { throw .cancelled }
      try await channel.deliver(file, named: name, progress: progress)
    }
  }

  private func record(_ book: Book, to destination: Destination, _ outcome: SendOutcome) async {
    // History is a convenience: failing to write it must not turn a delivered book into a failure.
    try? await history.append(
      SendRecord(bookID: book.id, destination: destination.kind, date: now(), outcome: outcome))
  }
}
