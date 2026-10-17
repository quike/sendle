import Foundation
import Observation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "ui")

/// The books being sent, one run at a time, and what came of them.
@Observable @MainActor
public final class SendQueueViewModel {
  /// Begins holding off App Nap and idle sleep, and returns what ends it.
  package typealias KeepAwake = @MainActor () -> @MainActor () -> Void

  package private(set) var rows: [QueueRow] = []
  package private(set) var destination: Destination?
  package private(set) var isRunning = false
  /// What the finished run comes to; nil while sending or when everything was cancelled.
  package private(set) var summary: Toast?
  /// Runs after each run, for example to show the new sends in the library.
  @ObservationIgnored package var onFinish: (@MainActor () async -> Void)?
  /// A book too large to email can go over USB while a Kindle is plugged in.
  @ObservationIgnored package var isKindleConnected: @MainActor () -> Bool = { false }

  @ObservationIgnored private var run: Task<Void, Never>?
  @ObservationIgnored private var endActivity: (@MainActor () -> Void)?
  private let sendBooks: SendBooks
  private let keepAwake: KeepAwake

  public convenience init(sendBooks: SendBooks) {
    self.init(sendBooks: sendBooks, keepAwake: Self.processActivity)
  }

  package init(sendBooks: SendBooks, keepAwake: @escaping KeepAwake) {
    self.sendBooks = sendBooks
    self.keepAwake = keepAwake
  }

  package var isEmpty: Bool { rows.isEmpty }

  /// The menu bar shows "↑ 2/3" while the second of three books is on its way.
  package var progressLabel: String? {
    guard isRunning, !rows.isEmpty else { return nil }
    let done = rows.filter(\.status.isFinished).count
    return "↑ \(min(done + 1, rows.count))/\(rows.count)"
  }

  /// A finished run with a failure stays on the red dot until it is cleared.
  package var needsAttention: Bool {
    !isRunning && rows.contains { if case .failed = $0.status { true } else { false } }
  }

  package var title: String {
    let sent = rows.filter { $0.status == .sent }.count
    let failed = failures.count
    if isRunning { return "Sending \(Self.books(rows.count))" }
    if sent == rows.count { return "Sent \(Self.books(sent))" }
    if sent > 0 { return "Sent \(sent) of \(rows.count) books" }
    if failed > 0, retryable.isEmpty { return "\(Self.books(failed)) may have been sent" }
    if failed > 0 { return "Couldn't send \(Self.books(failed))" }
    return "Sending cancelled"
  }

  package var subtitle: String {
    let place = "to \(destination?.chipTitle ?? "Kindle")"
    return isRunning ? "\(place) · close the panel anytime" : place
  }

  // MARK: Actions

  /// Starts a run and replaces the queue. Ignored while a run is in progress.
  package func send(_ books: [Book], to destination: Destination) {
    guard !isRunning, !books.isEmpty else { return }
    rows = books.map { QueueRow(book: $0, destination: destination.kind) }
    self.destination = destination
    summary = nil
    isRunning = true
    // A run goes on behind a closed panel, where nothing else keeps an accessory app awake.
    endActivity = keepAwake()
    let sendBooks = sendBooks
    run = Task { [weak self] in
      await sendBooks(books, to: destination) { [weak self] event in
        await self?.handle(event)
      }
      await self?.finish()
    }
  }

  /// Stops the current book; the rest are reported as cancelled.
  package func cancel() {
    run?.cancel()
  }

  /// An unconfirmed book may already be with Amazon, so a retry never resends it.
  package func retryFailed() {
    guard !isRunning, let destination else { return }
    send(retryable.map(\.book), to: destination)
  }

  package func dismiss() {
    guard !isRunning else { return }
    rows = []
    summary = nil
    destination = nil
  }

  package func waitUntilFinished() async {
    await run?.value
  }

  package func handle(_ event: SendEvent) {
    switch event {
    case .preparing(let id):
      update(id) { $0.status = .preparing }
    case .uploading(let id, let fraction):
      // A retry starts again at 0.
      update(id) { $0.status = .uploading(fraction) }
    case .sent(let id, let fixes):
      update(id) {
        $0.status = .sent
        $0.fixes = fixes
      }
    case .failed(let id, let failure):
      if failure != .cancelled {
        let detail = String(describing: failure)
        logger.error(
          "Sending \(id.rawValue, privacy: .private) failed: \(detail, privacy: .private)")
      }
      update(id) { $0.status = failure == .cancelled ? .cancelled : .failed(failure) }
    }
  }

  // MARK: Private

  private var failures: [QueueRow] {
    rows.filter { if case .failed = $0.status { true } else { false } }
  }

  private var retryable: [QueueRow] {
    rows.filter {
      switch $0.status {
      case .failed(.unconfirmed): false
      case .failed: true
      default: false
      }
    }
  }

  private func update(_ id: BookID, _ change: (inout QueueRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    change(&rows[index])
  }

  private func finish() async {
    isRunning = false
    endActivity?()
    endActivity = nil
    summary = makeSummary()
    await onFinish?()
  }

  private func makeSummary() -> Toast? {
    if let failed = retryable.first ?? failures.first, case .failed(let failure) = failed.status {
      return Toast(
        tone: .failure,
        ProblemPresenter.problem(for: failure, kindleConnected: isKindleConnected()))
    }
    let sent = rows.filter { $0.status == .sent }
    guard let first = sent.first else { return nil }
    let one = sent.count == 1
    if case .usb(let volume) = destination {
      return Toast(
        tone: .success,
        title: one
          ? "\(first.book.title) is on your Kindle" : "\(sent.count) books are on your Kindle",
        message: "Eject it before you unplug the cable.", fix: Fix("Eject", .eject(volume)))
    }
    return Toast(
      tone: .success,
      title: one ? "\(first.book.title) is on its way" : "\(sent.count) books are on their way",
      message: "Amazon delivers \(one ? "it" : "them") over Wi-Fi. If anything's off, Amazon "
        + "emails your sender address.")
  }

  private static func processActivity() -> @MainActor () -> Void {
    let activity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiated, reason: "Sending books to Kindle")
    return { ProcessInfo.processInfo.endActivity(activity) }
  }

  private static func books(_ count: Int) -> String {
    "\(count) \(count == 1 ? "book" : "books")"
  }
}
