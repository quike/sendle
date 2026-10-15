public enum SendStep: Hashable, Sendable {
  case prepareEPUB
  case convert(to: FileFormat)
  case deliver
}

public enum SendPlan: Hashable, Sendable {
  case send([SendStep])
  case blocked(SendFailure, suggestion: DestinationKind?)
}

public enum FormatPolicy {
  /// Amazon's Send to Kindle limit per email, read conservatively as decimal megabytes.
  public static let emailSizeLimit: Int64 = 50_000_000

  /// EPUB size is only known after packaging, so the email channel enforces the limit for EPUBs.
  public static func plan(
    for book: Book,
    to destination: DestinationKind,
    converterAvailable: Bool
  ) -> SendPlan {
    switch book.availability {
    case .protected: return .blocked(.protected, suggestion: nil)
    case .inCloudOnly: return .blocked(.inCloudOnly, suggestion: nil)
    case .missing: return .blocked(.missing, suggestion: nil)
    case .ready: break
    }
    switch (destination, book.format) {
    case (.email, .epub):
      return .send([.prepareEPUB, .deliver])
    case (.email, .pdf):
      if let size = book.sizeBytes, size > emailSizeLimit {
        return .blocked(.tooLarge(bytes: size, limit: emailSizeLimit), suggestion: .usb)
      }
      return .send([.deliver])
    case (.usb, .pdf):
      return .send([.deliver])
    case (.usb, .epub):
      guard converterAvailable else {
        return .blocked(.conversionUnavailable, suggestion: .email)
      }
      return .send([.prepareEPUB, .convert(to: .azw3), .deliver])
    }
  }
}
