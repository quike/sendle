import Foundation
import Observation
import SendleDomain

/// The area pills above the logs.
package enum LogAreaFilter: CaseIterable, Sendable {
  case all
  case email
  case usb
  case library
  case app

  package var title: String {
    switch self {
    case .all: "All"
    case .email: "Email"
    case .usb: "USB"
    case .library: "Library"
    case .app: "App"
    }
  }

  func includes(_ area: LogArea) -> Bool {
    switch self {
    case .all: true
    case .email: area == .mail
    case .usb: area == .usb || area == .boko
    case .library: area == .library || area == .epub
    case .app: area == .app
    }
  }
}

extension LogLevel {
  package var label: String {
    switch self {
    case .debug: "DEBUG"
    case .info: "INFO"
    case .warning: "WARN"
    case .error: "ERROR"
    }
  }
}

/// What Sendle did underneath, filtered by search, area and level.
@Observable @MainActor
public final class LogsViewModel {
  package var query = "" {
    didSet {
      if Self.words(in: query) != Self.words(in: oldValue) { closedDuringSearch = [] }
      refilter()
    }
  }
  package var area = LogAreaFilter.all {
    didSet { refilter() }
  }
  /// The lines on screen. A send's heading shows only while something under it does.
  package private(set) var visible: [LogEntry] = []
  /// The line to bring into view; `revealRequests` changes each time it is asked for.
  package private(set) var scrollTarget: Int?
  package private(set) var revealRequests = 0
  /// Whether the newest line is on screen, so new ones scroll into view.
  package var isAtBottom = true

  private var entries: [LogEntry] = []
  private var hiddenLevels: Set<LogLevel> = []
  private var expanded: Set<Int> = []
  /// Entries the search would open that the user closed since the query last changed.
  private var closedDuringSearch: Set<Int> = []
  @ObservationIgnored private var following: Task<Void, Never>?

  private let feed: any ActivityLogFeed
  private let clock: DateFormatter
  private let precise: DateFormatter

  public init(feed: any ActivityLogFeed, timeZone: TimeZone = .current) {
    self.feed = feed
    clock = Self.formatter("HH:mm:ss", timeZone)
    precise = Self.formatter("HH:mm:ss.SSS", timeZone)
  }

  /// Follows new lines while the screen is open.
  package func start() {
    refresh()
    guard following == nil else { return }
    let changes = feed.changes()
    following = Task { [weak self] in
      for await _ in changes {
        self?.refresh()
      }
    }
  }

  package func stop() {
    following?.cancel()
    following = nil
  }

  package func refresh() {
    entries = feed.entries()
    let live = entries.map(\.id)
    expanded.formIntersection(live)
    closedDuringSearch.formIntersection(live)
    refilter()
  }

  package func isShowing(_ level: LogLevel) -> Bool {
    !hiddenLevels.contains(level)
  }

  package func toggle(_ level: LogLevel) {
    if hiddenLevels.remove(level) == nil { hiddenLevels.insert(level) }
    refilter()
  }

  /// Open when the user opened it, or when a searched word sits past its first line, unless the
  /// user closed it during this search.
  package func isExpanded(_ entry: LogEntry) -> Bool {
    expanded.contains(entry.id)
      || (!closedDuringSearch.contains(entry.id) && matchesPastFirstLine(entry))
  }

  package func toggleExpanded(_ entry: LogEntry) {
    if isExpanded(entry) {
      expanded.remove(entry.id)
      closedDuringSearch.insert(entry.id)
    } else {
      expanded.insert(entry.id)
    }
  }

  /// Where the searched words fall in `text`.
  package func highlights(in text: String) -> [Range<String.Index>] {
    TextMatches.ranges(of: words, in: text)
  }

  package static func extraLines(in entry: LogEntry) -> Int {
    entry.message.split(separator: "\n", omittingEmptySubsequences: false).count - 1
  }

  package func time(of entry: LogEntry) -> String {
    clock.string(from: entry.date)
  }

  package func clear() {
    feed.clear()
    refresh()
  }

  /// The lines on screen in full, one after another, for pasting elsewhere.
  package func copyText() -> String {
    visible.map {
      "\(precise.string(from: $0.date)) \($0.level.label) \($0.area.tag) \($0.message)"
    }
    .joined(separator: "\n")
  }

  /// Opens the latest story of `subject` with every filter off.
  package func reveal(_ subject: LogSubject) {
    query = ""
    area = .all
    hiddenLevels = []
    refresh()
    scrollTarget = entries.last { $0.heading == subject }?.id
    isAtBottom = false
    revealRequests += 1
  }

  /// Opens at the newest line, following new ones.
  package func showNewest() {
    scrollTarget = nil
    isAtBottom = true
  }

  private var words: [Substring] {
    Self.words(in: query)
  }

  private static func words(in query: String) -> [Substring] {
    query.split(whereSeparator: \.isWhitespace)
  }

  private func matchesPastFirstLine(_ entry: LogEntry) -> Bool {
    let words = self.words
    guard !words.isEmpty, let newline = entry.message.firstIndex(of: "\n") else { return false }
    let rest = entry.message[entry.message.index(after: newline)...]
    return words.contains { rest.range(of: $0, options: TextMatches.options) != nil }
  }

  private func refilter() {
    let words = self.words
    var shown: [LogEntry] = []
    // A heading waiting for its first line, and where it goes when that line shows.
    var pending: (heading: LogEntry, index: Int)?
    for entry in entries where area.includes(entry.area) {
      let matches = TextMatches.contains(every: words, in: entry.message)
      if entry.heading != nil {
        pending = (entry, shown.count)
        if matches && !words.isEmpty && isShowing(entry.level) {
          shown.append(entry)
          pending = nil
        }
      } else if matches && isShowing(entry.level) {
        if let (heading, index) = pending, Self.belongs(entry, under: heading) {
          shown.insert(heading, at: index)
          pending = nil
        }
        shown.append(entry)
      }
    }
    visible = shown
  }

  /// A send's lines: its channel's, boko's for USB, and the EPUB fixes. Library reads and
  /// Sendle's housekeeping can fall in between without being part of it.
  private static func belongs(_ entry: LogEntry, under heading: LogEntry) -> Bool {
    switch (heading.area, entry.area) {
    case (_, .epub): true
    case (.usb, .boko): true
    default: entry.area == heading.area
    }
  }

  private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter
  }
}
