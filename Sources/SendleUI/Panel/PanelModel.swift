import AppKit
import CoreGraphics
import Foundation
import Observation
import SendleDomain
import SwiftUI

package enum PanelRoute: Equatable, Sendable {
  case library
  case setup
  case queue
  case logs
}

/// Which of the library's two sides shows while a Kindle is plugged in.
package enum LibrarySide: Hashable, Sendable {
  case library
  case kindle
}

/// The panel's state above its screens: which one shows, the settings sheet, keys, fixes and the
/// menu bar icon.
@Observable @MainActor
public final class PanelModel {
  package static let fullDiskAccessURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  package let library: LibraryViewModel
  package let setup: SetupViewModel
  package let settings: SettingsViewModel
  package let covers: CoverStore
  package let queue: SendQueueViewModel
  package let logs: LogsViewModel
  package let kindle: KindleViewModel
  package let pointer = PointerModel()
  package private(set) var route = PanelRoute.library
  package private(set) var side = LibrarySide.library
  package private(set) var isShowingSettings = false
  package private(set) var notice: Problem?
  /// The Kindle being ejected, while it is.
  package private(set) var ejecting: KindleVolume?
  /// The Kindle chip under the pointer.
  package var hoveredChip: KindleVolume?
  /// The Kindle chip, or its Eject, that has keyboard focus.
  package var focusedChip: KindleVolume?
  /// The duplicates of a USB send, while the user decides what to do with each.
  package private(set) var duplicateReview: DuplicateReviewModel?
  /// The edit details sheet, while it shows.
  package private(set) var bookDetails: BookDetailsViewModel?
  /// The read-only details of a book on the Kindle, while the sheet shows.
  package private(set) var kindleDetails: KindleDetailsViewModel?
  package private(set) var isSavingDetails = false
  /// The Kindle a send is checked against, while it is: read for duplicates, then its copies' ASINs
  /// planned against it. Another send would only race it.
  package private(set) var checkingKindle: KindleVolume?
  /// Bumped by ⌘F; the search field takes the keyboard when it changes.
  package private(set) var searchFocusRequests = 0
  /// The status item's centre, measured from the card's left edge, where the arrow points.
  public var arrowX: CGFloat = 200
  /// The side of the card with room on screen for the floating A–Z card.
  package var railSide = RailSide.trailing
  /// The whole card, or a shorter one on a screen without room for it.
  package var cardSize = Theme.cardSize

  @ObservationIgnored private weak var system: (any SystemActions)?
  @ObservationIgnored private let ejector: any KindleEjector
  @ObservationIgnored private let editDetails: EditBookDetails
  @ObservationIgnored private let log: any ActivityLog
  @ObservationIgnored private var accessWatch: Task<Void, Never>?
  /// Where the logs go back to, and whether the settings sheet was over it.
  private var beforeLogs = (route: PanelRoute.library, showedSettings: false)
  /// Bumped by every open and close, so an opening that a newer one replaced leaves the state alone.
  @ObservationIgnored private var session = 0
  /// What the review is about: sent, minus the skips, once it finishes. Keep both copies are named
  /// against the listing the duplicates were found in.
  @ObservationIgnored private var pendingSend: PendingSend?
  /// The send a finished review starts once its copies are planned.
  @ObservationIgnored private var reviewedSend: Task<Void, Never>?

  private typealias PendingSend = (books: [Book], destination: Destination, listing: KindleListing)

  public init(
    library: LibraryViewModel,
    setup: SetupViewModel,
    settings: SettingsViewModel,
    covers: CoverStore,
    queue: SendQueueViewModel,
    logs: LogsViewModel,
    kindle: KindleViewModel,
    editDetails: EditBookDetails,
    ejector: any KindleEjector,
    log: any ActivityLog = NoActivityLog()
  ) {
    self.library = library
    self.setup = setup
    self.settings = settings
    self.covers = covers
    self.queue = queue
    self.logs = logs
    self.kindle = kindle
    self.editDetails = editDetails
    self.ejector = ejector
    self.log = log
    library.reportProblem = { [weak self] problem in self?.show(notice: problem) }
    library.onKindleInputsChange = { [weak self] in self?.followKindle() }
    library.onSortChange = { [weak kindle] in kindle?.sort = $0 }
    library.onAuthorSortChange = { [weak kindle] in kindle?.authorSort = $0 }
    kindle.onMatchesChange = { [weak library] in library?.showKindleMatches($0) }
    settings.onChange = { [weak library] in await library?.refreshSettings() }
    queue.onFinish = { [weak self] in await self?.refreshAfterSend() }
    queue.isKindleConnected = { [weak library] in library?.isKindlePluggedIn ?? false }
  }

  /// The shell owns the panel, so it's attached after both exist.
  public func attach(_ system: any SystemActions) {
    self.system = system
  }

  /// The send bar's second line.
  package var sendBarHint: String {
    if let checkingKindle { return "Checking \(checkingKindle.name) for duplicates…" }
    return library.canSend ? "\(library.sendHint) · Esc to clear" : library.sendHint
  }

  public var statusItem: StatusItemState {
    let libraryFailed = if case .failed = library.state { true } else { false }
    return StatusItemState(
      symbolName: library.isKindlePluggedIn ? "book.closed.fill" : "book.closed",
      needsAttention: notice != nil || libraryFailed || queue.needsAttention,
      progress: queue.progressLabel)
  }

  package var isWaitingForAccess: Bool { accessWatch != nil }

  /// The logs button shows while Settings › General › Show logs is on.
  package var showsLogs: Bool { settings.showsLogs }

  /// Settings › General › Controls: the send bar and the A–Z bar inside the card, or floating.
  package var controls: ControlsStyle { library.controls }

  /// The room the window keeps around the card.
  package var windowMargins: EdgeInsets { FloatingControls.margins(side: railSide) }

  /// The send bar over the bottom of the library's books.
  package var showsSendBar: Bool {
    controls == .attached && side == .library && !library.selection.isEmpty
  }

  /// What the books keep clear at their bottom for the send bar.
  package var sendBarRoom: CGFloat { showsSendBar ? 64 : 0 }

  /// The send bar on its own card under the panel's.
  package var showsSendCard: Bool {
    controls == .floating && side == .library && !library.selection.isEmpty
      && areFloatingCardsUncovered
  }

  /// Where the books' A–Z bar floats, or nil while it sits inside them.
  package var floatingRailSide: RailSide? { controls == .floating ? railSide : nil }

  /// The A–Z bar may show on its own card beside the panel's.
  package var showsFloatingRail: Bool { controls == .floating && areFloatingCardsUncovered }

  /// The floating cards go with the books, so a sheet over them or another screen hides them.
  private var areFloatingCardsUncovered: Bool {
    route == .library && !isShowingSettings && duplicateReview == nil && bookDetails == nil
      && kindleDetails == nil
  }

  /// Kindle covers carry their format, as the library's do, until the format menu picks one.
  package var showsFormatOnKindleCovers: Bool { library.showsFormat && kindle.format == nil }

  /// The side switch's labels, each with how many books it holds.
  package func switchTitle(_ side: LibrarySide) -> String {
    switch side {
    case .library:
      "Library · \(library.books.count)"
    case .kindle:
      kindle.listing.map { "On Kindle · \($0.books.count)" } ?? "On Kindle"
    }
  }

  /// The Kindle side only exists while a Kindle is plugged in.
  package func showSide(_ side: LibrarySide) {
    guard side == .library || library.isKindlePluggedIn else { return }
    self.side = side
  }

  // MARK: Lifecycle

  /// Reads the library once, so the red dot can ask for access before the panel ever opens.
  public func launch() async {
    await settings.start()
    await library.start()
    await library.reload()
  }

  /// Library access is checked again every time the panel opens. The shell cancels this when the
  /// panel closes before it finishes; a newer open or close then owns the state.
  public func panelDidOpen() async {
    session += 1
    let opened = session
    await library.appear()
    guard opened == session else { return }
    guard !Task.isCancelled else { return panelDidClose() }
    if route == .logs { logs.start() }
    if library.needsAccess, route != .queue {
      showSetup(at: .libraryAccess)
    } else if route == .setup, setup.step == .libraryAccess {
      await libraryAccessArrived()
    }
  }

  public func panelDidClose() {
    session += 1
    hoveredChip = nil
    focusedChip = nil
    pointer.location = nil
    library.disappear()
    logs.stop()
    accessWatch?.cancel()
    accessWatch = nil
  }

  public func show(notice: Problem) {
    self.notice = notice
  }

  // MARK: Setup

  package func showSetup(at step: SetupStep) {
    route = .setup
    setup.begin(at: step)
    if step == .libraryAccess { watchForAccess() }
  }

  package func finishSetup() async {
    guard await setup.finish() else { return }
    await library.refreshSettings()
    route = .library
  }

  /// The Kindle email can be set up later from its chip.
  package func skipSetup() {
    route = .library
  }

  package func revealApp() {
    system?.revealApp()
  }

  /// A click on a book takes the keyboard back from the search field, so arrows reach the library.
  package func click(_ id: BookID, _ kind: ClickKind) {
    system?.endEditing()
    library.click(id, kind)
  }

  /// A Kindle that goes takes its side with it, and a destination that changes takes the review
  /// of a send to it.
  private func followKindle() {
    let volume = library.kindleVolume
    let books = library.books
    if volume == nil {
      side = .library
      kindleDetails = nil
    }
    if let pending = pendingSend, library.activeDestination != pending.destination {
      stopSend(to: pending.destination)
    }
    Task { await kindle.follow(volume, books: books) }
  }

  /// A USB send changed the Kindle, so it is read again before the history shows the send, or a
  /// book just copied would show as missing from it; an email send only changed what the history
  /// says about the library.
  private func refreshAfterSend() async {
    if queue.destination?.kind == .usb {
      await kindle.refresh()
      await library.refreshHistory()
    } else {
      await library.refreshHistory()
      await kindle.rematch()
    }
  }

  private func watchForAccess() {
    guard accessWatch == nil else { return }
    accessWatch = Task { [weak self] in
      guard let granted = await self?.setup.waitForLibraryAccess(), granted, !Task.isCancelled
      else { return }
      await self?.libraryAccessArrived()
    }
  }

  private func libraryAccessArrived() async {
    accessWatch = nil
    if setup.accessGranted(emailConfigured: library.hasKindleEmail) { route = .library }
  }

  // MARK: Sending

  package func sendSelection() async {
    await send(library.selectedBooks)
  }

  package func quickSend(_ id: BookID) async {
    guard let item = library.items.first(where: { $0.id == id && $0.canSend }) else { return }
    await send([item.book])
  }

  /// A USB send first reads the Kindle it goes to and asks about each book it already has.
  /// Without duplicates, or when the Kindle can't be read, it goes as it always did. A destination
  /// that changes during the check stops the send.
  private func send(_ books: [Book]) async {
    guard let destination = library.activeDestination, !books.isEmpty, !queue.isRunning,
      duplicateReview == nil, checkingKindle == nil
    else { return }
    guard case .usb(let volume) = destination else { return start(books, to: destination) }
    if ejecting == volume { return }
    system?.endEditing()
    checkingKindle = volume
    defer { checkingKindle = nil }
    let check = await kindle.duplicates(of: books, on: volume)
    guard library.activeDestination == destination, check != .interrupted else {
      return stopSend(to: destination)
    }
    var listing: [KindleBook] = []
    switch check {
    case .checked(let duplicates, let found) where !duplicates.isEmpty:
      guard !queue.isRunning else { return }
      pendingSend = (books, destination, found)
      duplicateReview = DuplicateReviewModel(cases: duplicates)
      return
    case .checked(_, let found):
      listing = found.books
    case .unreadable(let error):
      log.warning(
        .usb,
        "Couldn't check \(volume.name) for duplicates: \(Self.reason(error)); sending as before")
    case .interrupted:
      break
    }
    await planAndStart(books, to: destination, copies: [:], against: listing)
  }

  private static func reason(_ error: KindleListingError) -> String {
    switch error {
    case .unreadable(let detail): detail
    case .deviceDisconnected: "it was unplugged"
    case .cancelled: "the read was cancelled"
    }
  }

  /// Nothing goes to a Kindle whose books were checked against another one.
  private func stopSend(to destination: Destination) {
    cancelReview()
    if case .usb(let volume) = destination {
      show(notice: ProblemPresenter.kindleChangedWhileChecking(volume))
    }
  }

  private func start(
    _ books: [Book], to destination: Destination, copies: [BookID: KindleCopy] = [:]
  ) {
    system?.endEditing()
    queue.send(books, to: destination, copies: copies)
    _ = library.clearSelection()
    route = .queue
  }

  /// Plans the copies' ASINs against `listing` (see `KindleCopyPlanner`), then sends, unless the
  /// destination changed meanwhile.
  private func planAndStart(
    _ books: [Book], to destination: Destination, copies: [BookID: KindleCopy],
    against listing: [KindleBook]
  ) async {
    let planned = await kindle.plannedCopies(for: books, copies: copies, listing: listing)
    guard library.activeDestination == destination else { return stopSend(to: destination) }
    start(books, to: destination, copies: planned)
  }

  package func choose(_ choice: DuplicateChoice) {
    guard let review = duplicateReview else { return }
    review.choose(choice)
    if review.isFinished { closeReview(review) }
  }

  package func chooseDefault() {
    guard let review = duplicateReview else { return }
    review.chooseDefault()
    if review.isFinished { closeReview(review) }
  }

  /// Returns once a finished review has started its send, or found nothing to send.
  package func waitUntilReviewed() async {
    await reviewedSend?.value
  }

  /// Closing the sheet sends nothing.
  package func cancelReview() {
    duplicateReview = nil
    pendingSend = nil
  }

  /// The sheet closes at once; the books follow once their copies are planned.
  private func closeReview(_ review: DuplicateReviewModel) {
    guard let pending = pendingSend else { return cancelReview() }
    guard library.activeDestination == pending.destination else {
      return stopSend(to: pending.destination)
    }
    cancelReview()
    checkingKindle = pending.destination.volume
    reviewedSend = Task {
      await finishReview(review, of: pending)
      checkingKindle = nil
    }
  }

  /// Drops the skips, names each Keep both copy past the names the Kindle already uses, keeps the
  /// ASIN of each copy replaced, and sends.
  private func finishReview(_ review: DuplicateReviewModel, of pending: PendingSend) async {
    var taken = Set(
      pending.listing.books.filter { !$0.id.relativePath.contains("/") }
        .map { $0.stem.lowercased() })
    let kindleName = pending.destination.volume?.name ?? "the Kindle"
    var copies: [BookID: KindleCopy] = [:]
    var books: [Book] = []
    for book in pending.books {
      switch review.decisions[book.id] {
      case .skip?:
        log.info(.usb, "Skipped \(book.title): \(kindleName) already has it")
        continue
      case .keepBoth?:
        let copy = Self.keepBothCopy(of: book, taken: taken)
        let name = FileNaming.copyName(for: book, copy: copy)
        taken.insert(name.lowercased())
        if copy > 1 { copies[book.id] = .keepBoth(copy) }
        log.info(.usb, "Keeping both: \(book.title) goes as \(name)")
      case .replace?:
        guard let old = review.cases.first(where: { $0.id == book.id })?.match.book else { break }
        if let asin = old.asin { copies[book.id] = .replacing(asin: asin) }
        log.info(.usb, "Replacing documents/\(old.id.relativePath) on \(kindleName)")
      case nil:
        break
      }
      books.append(book)
    }
    guard !books.isEmpty else { return }
    await planAndStart(
      books, to: pending.destination, copies: copies, against: pending.listing.books)
  }

  /// An edited title or author gives the book a new name, which it takes while the Kindle has no
  /// file under it.
  private static func keepBothCopy(of book: Book, taken: Set<String>) -> Int {
    let renamed = !book.edits.fields.isDisjoint(with: [.title, .author, .writerName])
    if renamed, !taken.contains(FileNaming.copyName(for: book, copy: 1).lowercased()) { return 1 }
    return FileNaming.nextFreeCopy(for: book, taken: taken)
  }

  /// Back to the library from a finished queue, which is then cleared.
  package func finishQueue() {
    guard !queue.isRunning else { return }
    queue.dismiss()
    route = .library
  }

  /// Retry sends the failed books again; using another destination goes back to the library.
  package func performQueueFix() async {
    guard let action = queue.summary?.fix?.action else { return }
    switch action {
    case .retry:
      queue.retryFailed()
    case .useDestination, .eject:
      finishQueue()
      await perform(action)
    case .openPrivacySettings, .openSettings, .openURL:
      await perform(action)
    }
  }

  // MARK: Book details

  /// Store purchases and protected books can't be sent, so their details aren't edited either.
  package func canEditDetails(_ book: Book) -> Bool {
    !book.isStorePurchase && book.availability != .protected
  }

  /// Opens the sheet over the library's books, with the book's own year and ISBN when its file can
  /// be read.
  package func openDetails(_ id: BookID) async {
    guard canOpenDetails, let book = library.books.first(where: { $0.id == id }),
      canEditDetails(book)
    else { return }
    system?.endEditing()
    let fileValues = await kindle.edition(of: book)
    guard canOpenDetails else { return }
    let editDetails = editDetails
    bookDetails = BookDetailsViewModel(
      book: book, library: library.books, fileValues: fileValues,
      authorSort: library.authorSort, lastSend: library.latestSend(of: id), now: Date(),
      save: { (draft: BookDetailsDraft) async throws(EditDetailsError) in
        try await editDetails.save(draft, for: book, fileValues: fileValues)
      })
  }

  /// Nothing is saved.
  package func closeDetails() {
    bookDetails = nil
  }

  /// Opens the read-only sheet over the Kindle's books, linked to the library book it matches.
  package func openKindleDetails(_ id: KindleBookID) {
    guard isOnLibrary, side == .kindle, bookDetails == nil, duplicateReview == nil,
      kindleDetails == nil, checkingKindle == nil,
      let book = kindle.listing?.books.first(where: { $0.id == id })
    else { return }
    kindleDetails = KindleDetailsViewModel(book: book, library: libraryLink(for: id))
  }

  package func closeKindleDetails() {
    kindleDetails = nil
  }

  /// Closes the sheet and opens the matching library book's edit sheet, where it is scrolled to.
  package func editInLibrary() async {
    guard let link = kindleDetails?.library, link.canEdit else { return }
    closeKindleDetails()
    showSide(.library)
    library.letterJump.top = link.id
    await openDetails(link.id)
  }

  private func libraryLink(for id: KindleBookID) -> KindleDetailsViewModel.LibraryLink? {
    guard let matches = kindle.matches, let bookID = matches.libraryBook(for: id),
      let book = library.books.first(where: { $0.id == bookID })
    else { return nil }
    return KindleDetailsViewModel.LibraryLink(
      id: bookID, title: book.title, isSure: matches.byBook[bookID]?.confidence == .sure,
      canEdit: canEditDetails(book))
  }

  /// A click elsewhere, or another app taking the keyboard, leaves the panel open while the sheet
  /// shows, so typed edits stay and an image can be dragged in from Finder.
  package var holdsPanelOpen: Bool { bookDetails != nil }

  package var canSaveDetails: Bool { bookDetails?.canSave == true && !isSavingDetails }

  /// A saved sheet closes, and the library shows the edits once it reloads.
  package func saveDetails() async {
    guard let details = bookDetails, canSaveDetails else { return }
    isSavingDetails = true
    defer { isSavingDetails = false }
    guard await details.save() else { return }
    if bookDetails === details { bookDetails = nil }
    await library.reload()
  }

  package func chooseCoverImage() async {
    guard let details = bookDetails, details.canChangeCover,
      let url = await system?.chooseImage()
    else { return }
    _ = await loadCover(from: url, into: details)
  }

  /// False when the file isn't an image the sheet can take.
  package func dropCover(_ url: URL) async -> Bool {
    guard let details = bookDetails, details.canChangeCover else { return false }
    return await loadCover(from: url, into: details)
  }

  private var canOpenDetails: Bool {
    isOnLibraryBooks && bookDetails == nil && duplicateReview == nil && checkingKindle == nil
  }

  /// An image saving would refuse is refused here, so the sheet says why at once.
  private func loadCover(from url: URL, into details: BookDetailsViewModel) async -> Bool {
    let file = await Task.detached { CoverImageFile.read(url) }.value
    guard bookDetails === details else { return false }
    switch file {
    case .success(let file):
      details.setCover(file.data, preview: file.preview)
      return true
    case .failure(let error):
      details.refuseCover(error)
      return false
    }
  }

  // MARK: Logs

  /// Opens the logs over whatever shows; `subject` scrolls to the latest story of that send.
  package func openLogs(revealing subject: LogSubject? = nil) {
    if route != .logs { beforeLogs = (route, isShowingSettings) }
    isShowingSettings = false
    route = .logs
    logs.start()
    if let subject { logs.reveal(subject) } else { logs.showNewest() }
  }

  /// The screen the logs slide up over while they are open, otherwise the one showing.
  package var screenUnderLogs: PanelRoute { route == .logs ? beforeLogs.route : route }

  package func closeLogs() {
    logs.stop()
    route = beforeLogs.route
    isShowingSettings = beforeLogs.showedSettings
  }

  package func copyLogs() {
    system?.copy(logs.copyText())
  }

  // MARK: Ejecting

  /// A Kindle stays put while a book is being copied to it.
  package func canEject(_ volume: KindleVolume) -> Bool {
    ejecting == nil && !isCopying(to: volume)
  }

  /// Eject sits inside the Kindle's chip while the pointer or the keyboard is on it, and while it
  /// ejects.
  package func showsEject(in volume: KindleVolume) -> Bool {
    hoveredChip == volume || focusedChip == volume || ejecting == volume
  }

  /// What VoiceOver offers on the chip; nil where Eject would be refused.
  package func ejectActionName(for volume: KindleVolume) -> String? {
    canEject(volume) ? "Eject \(volume.name)" : nil
  }

  private func isCopying(to volume: KindleVolume) -> Bool {
    queue.isRunning && queue.destination == .usb(volume)
  }

  /// The Kindle's chip goes away by itself once it is unmounted; a failure says why. A Kindle
  /// that is already gone is what Eject was for, so it says nothing.
  package func eject(_ volume: KindleVolume) async {
    guard library.destinations.contains(.usb(volume)) else { return }
    guard !isCopying(to: volume) else {
      return show(notice: ProblemPresenter.ejectWhileCopying(volume))
    }
    guard ejecting == nil else { return }
    ejecting = volume
    defer { ejecting = nil }
    do throws(EjectError) {
      try await ejector.eject(volume)
    } catch {
      show(notice: ProblemPresenter.problem(for: error, ejecting: volume))
    }
  }

  // MARK: Settings sheet

  /// Nil opens the front page.
  package func openSettings(_ section: SettingsSection? = nil) async {
    await settings.open(at: section)
    isShowingSettings = true
  }

  /// A test saves the setup first, so Settings and the library show what it may have changed.
  package func sendTest(from form: EmailForm) async {
    await form.sendTest()
    await settings.reload()
    await library.refreshSettings()
  }

  /// Lets the user point Sendle at a boko somewhere else.
  package func chooseBoko() async {
    guard let tool = await system?.chooseProgram() else { return }
    await settings.chooseBoko(tool)
  }

  package func closeSettings() {
    isShowingSettings = false
  }

  package func saveSettings() async {
    guard await settings.save() else { return }
    await library.refreshSettings()
    isShowingSettings = false
  }

  // MARK: Keys

  /// Esc closes the innermost thing: the duplicates, the edit sheet, the Kindle book's sheet, the
  /// settings sheet, a finished queue or a setup that can wait, the search, the selection, then the
  /// panel. A running queue keeps going behind a closed panel.
  package func escape() {
    if duplicateReview != nil {
      cancelReview()
    } else if bookDetails != nil {
      closeDetails()
    } else if kindleDetails != nil {
      closeKindleDetails()
    } else if isShowingSettings {
      isShowingSettings = false
    } else if route == .logs {
      closeLogs()
    } else if route == .queue, !queue.isRunning {
      finishQueue()
    } else if route == .setup, !library.needsAccess {
      skipSetup()
    } else if route == .library, side == .kindle {
      if kindle.query.isEmpty { system?.closePanel() } else { kindle.query = "" }
    } else if route == .library, !library.query.isEmpty {
      library.query = ""
    } else if route == .library, library.clearSelection() {
      return
    } else {
      system?.closePanel()
    }
  }

  /// True when the key was used, so the shell swallows it. A held Return settles no duplicate
  /// the user hasn't seen, saves no details twice, and sends nothing after the sheet it saved.
  public func handle(_ key: KeyInput) -> Bool {
    guard let command = key.panelCommand else { return false }
    if duplicateReview != nil {
      switch command {
      case .escape: cancelReview()
      case .confirm: if !key.isRepeat { chooseDefault() }
      default: return false
      }
      return true
    }
    if bookDetails != nil {
      switch command {
      case .escape: closeDetails()
      case .confirm:
        if !key.isRepeat, canSaveDetails { Task { await saveDetails() } }
      default: return false
      }
      return true
    }
    if kindleDetails != nil {
      switch command {
      case .escape, .confirm: closeKindleDetails()
      default: return false
      }
      return true
    }
    switch command {
    case .escape:
      escape()
    case .confirm:
      return key.isRepeat ? false : confirm()
    case .openSettings:
      if !isShowingSettings { Task { await openSettings() } }
    case .move(let direction):
      guard isOnLibraryBooks else { return false }
      system?.endEditing()
      library.move(direction)
    case .selectAll:
      guard isOnLibraryBooks else { return false }
      library.selectAll()
    case .layout(let layout):
      guard isOnLibrary else { return false }
      Task { await library.setLayout(layout) }
    case .focusSearch:
      guard isOnLibrary else { return false }
      searchFocusRequests += 1
    case .refresh:
      guard isOnLibrary, side == .kindle else { return false }
      Task { await kindle.refresh() }
    case .editDetails:
      let selected = library.selectedBooks
      guard canOpenDetails, selected.count == 1, let book = selected.first,
        canEditDetails(book)
      else { return false }
      Task { await openDetails(book.id) }
    }
    return true
  }

  private var isOnLibrary: Bool { route == .library && !isShowingSettings }

  /// The library's books, which the Kindle side leaves unselectable.
  private var isOnLibraryBooks: Bool { isOnLibrary && side == .library }

  /// Return acts on the settings page, moves the setup on, sends the selection or leaves a finished
  /// queue.
  private func confirm() -> Bool {
    if isShowingSettings { return confirmSettings() }
    switch route {
    case .setup:
      switch setup.step {
      case .libraryAccess: return false
      case .kindleEmail: setup.continueToSender()
      case .sender: Task { await finishSetup() }
      }
    case .library:
      guard side == .library, !library.selection.isEmpty, library.canSend else { return false }
      Task { await sendSelection() }
    case .queue:
      guard !queue.isRunning else { return false }
      finishQueue()
    case .logs:
      return false
    }
    return true
  }

  /// Return saves the sender, adds a typed Kindle address, or opens the first search result.
  private func confirmSettings() -> Bool {
    switch settings.section {
    case .sender? where settings.hasEmailSetup:
      Task { await saveSettings() }
    case .kindle? where !settings.newKindleAddress.isEmpty:
      Task { await settings.addKindleAddress() }
    case nil:
      guard let first = settings.results.first else { return false }
      settings.choose(first)
    default:
      return false
    }
    return true
  }

  // MARK: Fixes

  package func perform(_ action: FixAction) async {
    switch action {
    case .openPrivacySettings:
      if let url = URL(string: Self.fullDiskAccessURL) { system?.open(url) }
    case .openSettings(let section):
      await openSettings(section)
    case .useDestination(let kind):
      await library.activate(kind)
    case .eject(let volume):
      await eject(volume)
    case .openURL(let url):
      system?.open(url)
    case .retry:
      await library.reload()
    }
  }

  package func performNoticeFix() async {
    let action = notice?.fix?.action
    notice = nil
    if let action { await perform(action) }
  }

  package func dismissNotice() {
    notice = nil
  }
}
