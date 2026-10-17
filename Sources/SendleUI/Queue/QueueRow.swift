import SendleDomain

package enum QueueStatus: Hashable, Sendable {
  case waiting
  case preparing
  case uploading(Double)
  case sent
  case failed(SendFailure)
  case cancelled

  package var isFinished: Bool {
    switch self {
    case .waiting, .preparing, .uploading: false
    case .sent, .failed, .cancelled: true
    }
  }
}

/// One book in the queue, as its row shows it.
package struct QueueRow: Identifiable, Hashable, Sendable {
  package enum Tone: Sendable {
    case waiting
    case active
    case sent
    case failed
  }

  package let book: Book
  package let destination: DestinationKind
  package var status: QueueStatus
  package var fixes: [EPUBFix]

  package init(
    book: Book,
    destination: DestinationKind = .email,
    status: QueueStatus = .waiting,
    fixes: [EPUBFix] = []
  ) {
    self.book = book
    self.destination = destination
    self.status = status
    self.fixes = fixes
  }

  package var id: BookID { book.id }

  /// Amazon's result arrives later by email, so an emailed book is never called delivered. A
  /// copy over USB is on the Kindle once it's done.
  package var detail: String {
    switch (status, destination) {
    case (.waiting, _): "Waiting"
    case (.preparing, _) where book.format == .pdf: "Preparing"
    case (.preparing, .email): "Preparing the EPUB"
    case (.preparing, .usb): "Converting with boko"
    // Servers scan a message before they answer, for up to two minutes.
    case (.uploading(let fraction), .email) where fraction >= 1:
      "Waiting for the mail server to confirm"
    case (.uploading(let fraction), .email): "Uploading · \(Self.percent(fraction))%"
    case (.uploading(let fraction), .usb): "Copying · \(Self.percent(fraction))%"
    case (.sent, .email): "Sent to Amazon · arrives in a few minutes"
    case (.sent, .usb): "On your Kindle"
    case (.failed(let failure), _): ProblemPresenter.problem(for: failure).title
    case (.cancelled, _): "Cancelled"
    }
  }

  package var tone: Tone {
    switch status {
    case .waiting, .cancelled: .waiting
    case .preparing, .uploading: .active
    case .sent: .sent
    case .failed: .failed
    }
  }

  /// "Fixed 2 issues Amazon rejects (language, encoding)", in the order the fixes ran.
  package var fixesNote: String? {
    guard !fixes.isEmpty else { return nil }
    let names = fixes.map { fix in
      switch fix {
      case .addedXMLDeclaration: "encoding"
      case .addedLanguage: "language"
      case .removedBodyIDLinks: "links"
      case .removedEmptyImages: "images"
      }
    }
    let issues = fixes.count == 1 ? "issue" : "issues"
    let list = names.joined(separator: ", ")
    return destination == .usb
      ? "Fixed \(fixes.count) EPUB \(issues) (\(list))"
      : "Fixed \(fixes.count) \(issues) Amazon rejects (\(list))"
  }

  private static func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
  }
}
