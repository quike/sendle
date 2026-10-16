import Foundation
import Observation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "ui")

/// The books being sent, one run at a time, and what came of them.
@Observable @MainActor
public final class SendQueueViewModel {
  package private(set) var rows: [QueueRow] = []
  package private(set) var destination: Destination?
  package private(set) var isRunning = false
  /// What the finished run comes to; nil while sending or when everything was cancelled.
  package private(set) var summary: Toast?
  /// Runs after each run, for example to show the new sends in the library.
  @ObservationIgnored package var onFinish: (@MainActor () async -> Void)?

  @ObservationIgnored private var run: Task<Void, Never>?
  private let sendBooks: SendBooks

  public init(sendBooks: SendBooks) {
    self.sendBooks = sendBooks
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
    if failed > 0 { return "Couldn't send \(Self.books(failed))" }
    return "Sending cancelled"
  }

  package var subtitle: String {
    let place = "to \(destination?.chipTitle ?? "Kindle")"
    return isRunning ? "\(place) · close the panel anytime" : place
  }

  // MARK: Actions

  /// Starts a run. A second one waits until the first has finished and been looked at.
  package func send(_ books: [Book], to destination: Destination) {
    guard !isRunning, !books.isEmpty else { return }
    rows = books.map { QueueRow(book: $0) }
    self.destination = destination
    summary = nil
    isRunning = true
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

  package func retryFailed() {
    guard !isRunning, let destination else { return }
    send(failures.map(\.book), to: destination)
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
        logger.error(
          "Sending \(id.rawValue, privacy: .private) failed: \(String(describing: failure), privacy: .private)"
        )
      }
      update(id) { $0.status = failure == .cancelled ? .cancelled : .failed(failure) }
    }
  }

  // MARK: Private

  private var failures: [QueueRow] {
    rows.filter { if case .failed = $0.status { true } else { false } }
  }

  private func update(_ id: BookID, _ change: (inout QueueRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    change(&rows[index])
  }

  private func finish() async {
    isRunning = false
    summary = makeSummary()
    await onFinish?()
  }

  private func makeSummary() -> Toast? {
    if let failed = failures.first, case .failed(let failure) = failed.status {
      return Toast(tone: .failure, ProblemPresenter.problem(for: failure))
    }
    let sent = rows.filter { $0.status == .sent }
    guard let first = sent.first else { return nil }
    let one = sent.count == 1
    return Toast(
      tone: .success,
      title: one ? "\(first.book.title) is on its way" : "\(sent.count) books are on their way",
      message: "Amazon delivers \(one ? "it" : "them") over Wi-Fi. If anything's off, Amazon "
        + "emails your sender address.")
  }

  private static func books(_ count: Int) -> String {
    "\(count) \(count == 1 ? "book" : "books")"
  }
}
