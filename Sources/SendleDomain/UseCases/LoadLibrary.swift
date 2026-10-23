import Foundation

public struct LoadLibrary: Sendable {
  private let library: any BooksLibrary
  private let inspector: any ProtectionInspector
  private let editStore: any MetadataEditStore
  private let settings: (any SettingsStore)?
  private let log: any ActivityLog
  /// Books' folder changes about once a second while someone reads, so only news is logged.
  private let lastReport = LastReport()

  public init(
    library: any BooksLibrary,
    inspector: any ProtectionInspector,
    edits: any MetadataEditStore = NoMetadataEdits(),
    settings: (any SettingsStore)? = nil,
    log: any ActivityLog = NoActivityLog()
  ) {
    self.library = library
    self.inspector = inspector
    self.editStore = edits
    self.settings = settings
    self.log = log
  }

  /// Books newest first, with DRM-protected ones shown and the user's edits applied. Only local
  /// files are inspected, so reading the library never triggers an iCloud download.
  public func callAsFunction() async throws(LibraryError) -> [Book] {
    let clock = ContinuousClock()
    let start = clock.now
    let books: [Book]
    do throws(LibraryError) {
      books = try await library.books()
    } catch {
      let report = "Couldn't read the Books library: \(error.logDescription)"
      if lastReport.replace(with: report) { log.error(.library, report) }
      throw error
    }
    let edits = await editStore.edits()
    let authorSort = await settings?.load().authorSort ?? .surname
    let shown =
      books
      .map { book in
        guard book.availability == .ready, inspector.isProtected(book) else { return book }
        var protected = book
        protected.availability = .protected
        return protected
      }
      .map {
        edits.apply(to: $0, authorSort: authorSort, coverFolder: editStore.coverFolder)
      }
      .sorted { lhs, rhs in
        if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
    let report = Self.summary(of: shown)
    if lastReport.replace(with: report) {
      log.info(.library, "\(report) in \(Elapsed.text(clock.now - start))")
    }
    return shown
  }

  /// Emits whenever the library may have changed. Ends at once when the library can't be watched.
  public func changes() -> AsyncStream<Void> {
    library.changes()
  }

  /// "Read 523 books (12 protected, 3 only in iCloud, 1 missing)".
  private static func summary(of books: [Book]) -> String {
    let details = [
      (Availability.protected, "protected"), (.inCloudOnly, "only in iCloud"),
      (.missing, "missing"),
    ]
    .compactMap { availability, name in
      let count = books.filter { $0.availability == availability }.count
      return count > 0 ? "\(count) \(name)" : nil
    }
    let read = "Read \(books.count) \(books.count == 1 ? "book" : "books")"
    return details.isEmpty ? read : "\(read) (\(details.joined(separator: ", ")))"
  }
}

/// The last thing reported, so a repeat can be left out.
private final class LastReport: @unchecked Sendable {
  private let lock = NSLock()
  private var text: String?

  /// Remembers `report` and says whether it differs from the last one.
  func replace(with report: String) -> Bool {
    lock.withLock {
      defer { text = report }
      return text != report
    }
  }
}
