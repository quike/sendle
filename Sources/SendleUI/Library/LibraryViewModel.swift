import Foundation
import Observation
import SendleDomain
import os

private let logger = Logger(subsystem: "io.github.quike.Sendle", category: "ui")

package enum LibraryState: Equatable, Sendable {
  case loading
  case loaded
  case failed(Problem)
}

/// The books, search, filters, layout, destinations and selection behind every layout.
@Observable @MainActor
public final class LibraryViewModel {
  package private(set) var state = LibraryState.loading
  package private(set) var books: [Book] = []
  package private(set) var needsAccess = false
  package var query = "" {
    didSet {
      refreshItems()
      if query != oldValue { scrollToTop() }
    }
  }
  package var filter = LibraryFilter.all {
    didSet {
      refreshItems()
      if filter != oldValue { scrollToTop() }
    }
  }
  /// Nil shows every format.
  package var format: BookFormat? {
    didSet {
      refreshItems()
      if format != oldValue { scrollToTop() }
    }
  }
  package private(set) var kindleMatches: KindleMatches?
  package private(set) var layout = LibraryLayout.grid
  package private(set) var sort = LibrarySort.recent
  package private(set) var jumpBar = JumpBarStyle.full
  package private(set) var controls = ControlsStyle.attached
  package private(set) var showsFormat = true
  /// The books the filter and search show, in the sort's order. Built once per change: with
  /// hundreds of books, building them on every read slowed each render.
  package private(set) var items: [BookItemViewModel] = []
  /// The newest books on screen, whatever the sort, for the shelf.
  package private(set) var recentItems: [BookItemViewModel] = []
  package let letterJump = LetterJump<BookID>()
  /// Bumped when a new sort, filter or search should start at the top of the list.
  package private(set) var scrollToTopRequests = 0
  package private(set) var destinations: [Destination] = []
  package private(set) var hasKindleEmail = false
  package private(set) var preferredDestination = DestinationKind.email
  /// The Kindle chosen among several. It isn't saved: a Kindle's id is where it mounts.
  private var preferredVolume: KindleVolume?
  /// The Kindle read while email is the destination: it stays while plugged in, so another one
  /// arriving doesn't switch what the Kindle side shows.
  private var readVolume: KindleVolume?
  package private(set) var selection = Selection()
  package var hovered: BookID?
  /// Told when a reload fails but the books from the last good one stay on screen.
  @ObservationIgnored package var reportProblem: (@MainActor (Problem) -> Void)?
  /// Told when the books or the Kindle to read change.
  @ObservationIgnored package var onKindleInputsChange: (@MainActor () -> Void)?
  /// Told of the sort in force, once it is read and each time it changes.
  @ObservationIgnored package var onSortChange: (@MainActor (LibrarySort) -> Void)?

  private var sends: [BookID: BookSends] = [:]
  private var volumes: [KindleVolume] = []
  private var converterAvailable = false
  private var isVisible = false
  private var watcher: Task<Void, Never>?
  private var watcherGeneration = 0
  private var destinationUpdates: Task<Void, Never>?
  @ObservationIgnored private var reloading: Task<Void, Never>?

  private let loadLibrary: LoadLibrary
  private let observeDestinations: ObserveDestinations
  private let settings: any SettingsStore
  private let history: any SendHistoryStore
  private let converter: any FormatConverter
  private let now: @Sendable () -> Date

  public init(
    loadLibrary: LoadLibrary,
    observeDestinations: ObserveDestinations,
    settings: any SettingsStore,
    history: any SendHistoryStore,
    converter: any FormatConverter,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.loadLibrary = loadLibrary
    self.observeDestinations = observeDestinations
    self.settings = settings
    self.history = history
    self.converter = converter
    self.now = now
  }

  package var summary: String {
    let sendable = books.filter { $0.availability == .ready }.count
    return "\(books.count) \(books.count == 1 ? "book" : "books") · \(sendable) sendable"
  }

  /// The saved choice while it's available, otherwise the first destination there is.
  package var activeDestination: Destination? {
    let preferred = destinations.filter { $0.kind == preferredDestination }
    return preferred.first { $0.volume?.id == preferredVolume?.id } ?? preferred.first
      ?? destinations.first
  }

  /// The kind the library plans its books for and wears the colour of: the active destination's, or the saved choice.
  package var activeKind: DestinationKind { activeDestination?.kind ?? preferredDestination }

  /// The scopes on offer: the Kindle ones once the plugged-in Kindle has been read.
  package var filters: [LibraryFilter] {
    LibraryFilter.allCases.filter { kindleMatches != nil || !$0.needsKindle }
  }

  /// Covers carry their format only where the format menu lets formats mix.
  package var showsFormatOnCovers: Bool { showsFormat && format == nil }

  package var isKindlePluggedIn: Bool { !volumes.isEmpty }

  /// The Kindle to read: the active destination's when it is USB, otherwise the one already read
  /// while it is plugged in, otherwise the first.
  package var kindleVolume: KindleVolume? { activeDestination?.volume ?? readVolume }

  /// Something to send to; the selection itself only ever holds books that can go there.
  package var canSend: Bool { activeDestination != nil }

  package var sendHint: String {
    canSend ? "Return to send" : "Set up your Kindle email first"
  }

  package var quickSendHelp: String {
    activeDestination.map { "Send to \($0.spokenName)" } ?? "Set up your Kindle email first"
  }

  package var selectedBooks: [Book] {
    items.filter { selection.contains($0.id) }.map(\.book)
  }

  // MARK: Lifecycle

  /// Reads the remembered layout and destination, then follows Kindles for the app's lifetime.
  package func start() async {
    let saved = await settings.load()
    layout = saved.layout
    sort = saved.sort
    jumpBar = saved.jumpBar
    controls = saved.controls
    showsFormat = saved.showsFormat
    preferredDestination = saved.activeDestination
    hasKindleEmail = saved.email != nil
    converterAvailable = converter.isAvailable
    refreshItems()
    onSortChange?(sort)
    let updates = observeDestinations()
    destinationUpdates = Task { [weak self] in
      for await destinations in updates {
        guard let self else { return }
        self.show(destinations)
      }
    }
  }

  /// boko is looked for again, in case it was installed since the panel last opened.
  package func appear() async {
    isVisible = true
    converterAvailable = converter.isAvailable
    await reload()
  }

  /// Books' library files stay unwatched while nobody looks.
  package func disappear() {
    isVisible = false
    watcher?.cancel()
    watcher = nil
  }

  /// Reloads run one after another, so a slow older read can't replace a newer one.
  package func reload() async {
    let previous = reloading
    let next = Task { [weak self] in
      await previous?.value
      await self?.load()
    }
    reloading = next
    await next.value
  }

  /// What the plugged-in Kindle holds, or nil once it's gone; its scopes go with it.
  package func showKindleMatches(_ matches: KindleMatches?) {
    kindleMatches = matches
    if matches == nil, filter.needsKindle {
      filter = .all
    } else {
      refreshItems()
    }
  }

  package func refreshHistory() async {
    await readHistory()
    refreshItems()
  }

  /// A new Kindle email or boko shows at once; the destination stream only re-reads the email
  /// when a Kindle moves.
  package func refreshSettings() async {
    let saved = await settings.load()
    let email = saved.email?.kindleAddress
    hasKindleEmail = email != nil
    jumpBar = saved.jumpBar
    controls = saved.controls
    showsFormat = saved.showsFormat
    converterAvailable = converter.isAvailable
    show(ObserveDestinations.destinations(email: email, volumes: volumes))
  }

  // MARK: Choices

  package func setLayout(_ layout: LibraryLayout) async {
    guard layout != self.layout else { return }
    self.layout = layout
    await save { $0.layout = layout }
  }

  package func setSort(_ sort: LibrarySort) async {
    guard sort != self.sort else { return }
    self.sort = sort
    refreshItems()
    scrollToTop()
    onSortChange?(sort)
    await save { $0.sort = sort }
  }

  package func activate(_ kind: DestinationKind) async {
    preferredDestination = kind
    refreshItems()
    onKindleInputsChange?()
    await save { $0.activeDestination = kind }
  }

  package func activate(_ destination: Destination) async {
    if let volume = destination.volume { preferredVolume = volume }
    await activate(destination.kind)
  }

  package func click(_ id: BookID, _ kind: ClickKind) {
    selection.click(id, kind, in: items)
  }

  package func selectAll() {
    selection.selectAll(in: items)
  }

  /// False when there was nothing to clear, so Esc can move on to closing things.
  package func clearSelection() -> Bool {
    guard !selection.isEmpty else { return false }
    selection.clear()
    return true
  }

  package func move(_ direction: MoveDirection) {
    selection.move(direction, columns: layout == .grid ? 3 : 1, in: items)
  }

  // MARK: Private

  /// A failure other than lost access keeps the books already shown and says so.
  private func load() async {
    do {
      let loaded = try await loadLibrary()
      await readHistory()
      books = loaded
      needsAccess = false
      state = .loaded
      watchForChanges()
    } catch {
      let problem = ProblemPresenter.problem(for: error)
      if error != .accessDenied, state == .loaded, !books.isEmpty {
        reportProblem?(problem)
      } else {
        books = []
        needsAccess = error == .accessDenied
        state = .failed(problem)
      }
    }
    refreshItems()
    onKindleInputsChange?()
  }

  private func readHistory() async {
    sends = LibraryItems.sendsByBook(in: await history.records())
  }

  private func show(_ destinations: [Destination]) {
    self.destinations = destinations
    volumes = destinations.compactMap {
      if case .usb(let volume) = $0 { volume } else { nil }
    }
    if readVolume.map({ !volumes.contains($0) }) ?? true { readVolume = volumes.first }
    refreshItems()
    onKindleInputsChange?()
  }

  /// Rebuilds what the layouts show, and drops selected books that are no longer among it.
  private func refreshItems() {
    let newestFirst = LibraryItems.make(
      books: books, sends: sends, filter: filter, format: format, query: query,
      destination: activeKind, converterAvailable: converterAvailable, kindle: kindleMatches,
      now: now())
    items = LibraryOrder.sorted(newestFirst, by: sort, book: \.book)
    recentItems = Array(newestFirst.prefix(8))
    letterJump.index = sort == .recent ? nil : AlphabetIndex(books: items.map(\.book), sort: sort)
    selection.keep(in: items)
  }

  private func scrollToTop() {
    letterJump.top = nil
    scrollToTopRequests += 1
  }

  /// The stream ends at once when Books' folder can't be watched; the next good load tries again.
  private func watchForChanges() {
    guard isVisible, watcher == nil else { return }
    let changes = loadLibrary.changes()
    watcherGeneration += 1
    let generation = watcherGeneration
    watcher = Task { [weak self] in
      for await _ in changes {
        await self?.reload()
      }
      if self?.watcherGeneration == generation { self?.watcher = nil }
    }
  }

  private func save(_ change: @Sendable (inout AppSettings) -> Void) async {
    do {
      try await settings.update(change)
    } catch {
      logger.error("Could not save a panel choice: \(String(describing: error))")
    }
  }
}

extension LibrarySort {
  package var title: String {
    switch self {
    case .recent: "Recently added"
    case .title: "Title"
    case .author: "Author"
    }
  }
}

extension DestinationKind {
  package var symbol: String {
    switch self {
    case .email: "envelope.fill"
    case .usb: "cable.connector"
    }
  }
}

extension Destination {
  var volume: KindleVolume? {
    if case .usb(let volume) = self { volume } else { nil }
  }

  /// What chips and the Send button show beside the destination's icon.
  package var label: String {
    switch self {
    case .email: "Kindle email"
    case .usb(let volume): volume.name
    }
  }

  package var symbol: String { kind.symbol }

  /// The name where no icon can go: tooltips, VoiceOver and sentences.
  package var spokenName: String {
    switch self {
    case .email: "Kindle email"
    case .usb(let volume): "\(volume.name) (USB)"
    }
  }

  package var chipHelp: String {
    switch self {
    case .email(let address): "Quick-send emails \(address.rawValue)"
    case .usb(let volume): "Quick-send copies to \(volume.name)"
    }
  }
}
