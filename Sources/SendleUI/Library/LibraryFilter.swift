import SendleDomain

package enum LibraryFilter: String, CaseIterable, Sendable {
  case all
  case epub
  case pdf
  case notSent

  package var title: String {
    switch self {
    case .all: "All"
    case .epub: "EPUB"
    case .pdf: "PDF"
    case .notSent: "Not sent"
    }
  }

  func includes(_ book: Book, wasSent: Bool) -> Bool {
    switch self {
    case .all: true
    case .epub: book.format == .epub
    case .pdf: book.format == .pdf
    case .notSent: !wasSent
    }
  }
}
