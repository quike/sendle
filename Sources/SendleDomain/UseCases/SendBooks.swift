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
  private let log: any ActivityLog

  public init(
    channels: any DeliveryChannelFactory,
    preparer: any EPUBPreparer,
    converter: any FormatConverter,
    staging: any StagingArea,
    history: any SendHistoryStore,
    now: @escaping @Sendable () -> Date = { Date() },
    retryDelay: Duration = .seconds(2),
    sleep: @escaping Sleep = { try? await Task.sleep(for: $0) },
    log: any ActivityLog = NoActivityLog()
  ) {
    self.channels = channels
    self.preparer = preparer
    self.converter = converter
    self.staging = staging
    self.history = history
    self.now = now
    self.retryDelay = retryDelay
    self.sleep = sleep
    self.log = log
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
    let area = destination.logArea
    log.heading(.book(book.id), area, "\(book.title) · \(destination.logName)")
    let steps: [SendStep]
    switch FormatPolicy.plan(
      for: book, to: destination.kind, converterAvailable: converter.isAvailable)
    {
    case .blocked(let reason, _):
      log.warning(area, "Not sent: \(reason.logDescription)")
      return .failed(book.id, reason)
    case .send(let planned): steps = planned
    }
    log.debug(area, "Plan: \(Self.describe(steps))")
    await onEvent(.preparing(book.id))
    do throws(SendFailure) {
      let directory = try staging.makeDirectory()
      defer { staging.remove(directory) }
      let file = try await run(steps, for: book, to: destination, in: directory, onEvent: onEvent)
      await record(book, to: destination, .sent)
      log.info(area, destination.kind == .usb ? "On the Kindle" : "Sent")
      return .sent(book.id, fixes: file.fixes)
    } catch {
      if case .unconfirmed = error {
        // The server may still deliver it, cancelled or not.
        await record(book, to: destination, .unconfirmed)
        log.warning(area, "Not confirmed: \(error.logDescription)")
        return .failed(book.id, error)
      }
      let failure = Task.isCancelled ? .cancelled : error
      if failure == .cancelled {
        log.info(area, "Cancelled")
      } else {
        await record(book, to: destination, .failed)
        log.error(area, "Not sent: \(failure.logDescription)")
      }
      return .failed(book.id, failure)
    }
  }

  private static func describe(_ steps: [SendStep]) -> String {
    let names = steps.map { step in
      switch step {
      case .prepareEPUB: "prepare the EPUB"
      case .convert(let format): "convert it to \(format.rawValue.uppercased())"
      case .deliver: "deliver it"
      }
    }
    guard names.count > 1 else { return names.joined() }
    return names.dropLast().joined(separator: ", ") + ", then " + (names.last ?? "")
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
        logFixes(file.fixes)
      case .convert(let format):
        let converted = try await converter.convert(file, to: format, in: directory)
        file = PreparedFile(
          url: converted.url, format: converted.format, fixes: file.fixes, edition: file.edition)
      case .deliver:
        let channel = try await channels.channel(for: destination)
        try await deliver(
          Self.seeded(file, for: book, to: destination),
          named: FileNaming.deliveryName(for: book, to: destination.kind), via: channel,
          to: destination
        ) { fraction in
          await onEvent(.uploading(book.id, fraction: fraction))
        }
      }
    }
    return file
  }

  private static func seeded(
    _ file: PreparedFile, for book: Book, to destination: Destination
  ) -> PreparedFile {
    guard destination.kind == .usb, file.format == .azw3 else { return file }
    return PreparedFile(
      url: file.url, format: file.format, fixes: file.fixes, edition: file.edition,
      asinSeed: FileNaming.asinSeed(for: book, edition: file.edition, copy: 1))
  }

  private func deliver(
    _ file: PreparedFile,
    named name: String,
    via channel: any DeliveryChannel,
    to destination: Destination,
    progress: @Sendable (Double) async -> Void
  ) async throws(SendFailure) {
    do throws(SendFailure) {
      try await channel.deliver(file, named: name, progress: progress)
    } catch {
      guard error.isRetryable, !Task.isCancelled else { throw error }
      log.warning(
        destination.logArea,
        "\(error.logDescription.prefix(1).uppercased())\(error.logDescription.dropFirst()); "
          + "trying again in \(retryDelay.components.seconds) seconds")
      await sleep(retryDelay)
      if Task.isCancelled { throw .cancelled }
      try await channel.deliver(file, named: name, progress: progress)
    }
  }

  private func logFixes(_ fixes: [EPUBFix]) {
    guard !fixes.isEmpty else { return log.debug(.epub, "The EPUB needed no fixes") }
    let names = fixes.map { fix in
      switch fix {
      case .addedXMLDeclaration: "added the XML declaration"
      case .addedLanguage: "added its language"
      case .removedBodyIDLinks: "removed links to body IDs"
      case .removedEmptyImages: "removed images without a source"
      }
    }
    log.info(.epub, "Fixed the EPUB: \(names.joined(separator: ", "))")
  }

  private func record(_ book: Book, to destination: Destination, _ outcome: SendOutcome) async {
    // History is a convenience: failing to write it must not turn a delivered book into a failure.
    do throws(StorageError) {
      try await history.append(
        SendRecord(bookID: book.id, destination: destination.kind, date: now(), outcome: outcome))
    } catch {
      log.warning(.app, "Couldn't add the send to the history: \(error.detail)")
    }
  }
}

extension Destination {
  /// The area its sends are logged under.
  var logArea: LogArea {
    switch self {
    case .email: .mail
    case .usb: .usb
    }
  }

  /// "reader@kindle.com" or "Paperwhite (USB)".
  var logName: String {
    switch self {
    case .email(let address): address.rawValue
    case .usb(let volume): "\(volume.name) (USB)"
    }
  }
}
