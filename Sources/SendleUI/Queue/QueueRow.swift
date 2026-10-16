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
  package var status: QueueStatus
  package var fixes: [EPUBFix]

  package init(book: Book, status: QueueStatus = .waiting, fixes: [EPUBFix] = []) {
    self.book = book
    self.status = status
    self.fixes = fixes
  }

  package var id: BookID { book.id }

  /// Amazon's result arrives later by email, so a sent book is never called delivered.
  package var detail: String {
    switch status {
    case .waiting: "Waiting"
    case .preparing: book.format == .epub ? "Preparing the EPUB" : "Preparing"
    // Servers scan a message before they answer, for up to two minutes.
    case .uploading(let fraction) where fraction >= 1: "Waiting for the mail server to confirm"
    case .uploading(let fraction): "Uploading · \(Int((fraction * 100).rounded()))%"
    case .sent: "Sent to Amazon · arrives in a few minutes"
    case .failed(let failure): ProblemPresenter.problem(for: failure).title
    case .cancelled: "Cancelled"
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
    return "Fixed \(fixes.count) \(issues) Amazon rejects (\(names.joined(separator: ", ")))"
  }
}
