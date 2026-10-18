import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
final class FakeSystemActions: SystemActions {
  var opened: [URL] = []
  var revealedApp = 0
  var closedPanel = 0
  var endedEditing = 0

  func open(_ url: URL) { opened.append(url) }
  func revealApp() { revealedApp += 1 }
  func closePanel() { closedPanel += 1 }
  func endEditing() { endedEditing += 1 }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PanelModelTests {
  let library = FakeBooksLibrary(.success([.fixture(id: "a"), .fixture(id: "b")]))
  let monitor = FakeDestinationMonitor()
  let system = FakeSystemActions()
  let history = InMemorySendHistoryStore()
  let ejector = FakeKindleEjector()

  /// `onSleep` runs each time setup waits between access checks.
  /// `channel` delivers every send and test email; `ejector` replaces the suite's.
  func makePanel(
    _ saved: AppSettings = AppSettings(email: .fixture),
    channel: FakeDeliveryChannel = FakeDeliveryChannel(),
    ejector: FakeKindleEjector? = nil,
    onSleep: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(60)) }
  ) -> (PanelModel, InMemorySettingsStore) {
    let settings = InMemorySettingsStore(saved)
    let converter = FakeFormatConverter(isAvailable: false)
    let configure = ConfigureEmail(settings: settings, secrets: MemorySecretStore())
    let channels = FakeDeliveryChannelFactory(channel: channel)
    let staging = FakeStagingArea()
    let sendTest = SendTestEmail(settings: settings, channels: channels, staging: staging)
    let libraryModel = LibraryViewModel(
      loadLibrary: LoadLibrary(library: library, inspector: StubProtectionInspector()),
      observeDestinations: ObserveDestinations(monitor: monitor, settings: settings),
      settings: settings, history: history, converter: FakeFormatConverter(isAvailable: false))
    let setup = SetupViewModel(
      configure: configure, sendTest: sendTest,
      checkAccess: {
        await libraryModel.reload()
        return !libraryModel.needsAccess
      },
      sleep: { _ in await onSleep() })
    let panel = PanelModel(
      library: libraryModel, setup: setup,
      settings: SettingsViewModel(
        configure: configure, sendTest: sendTest,
        addresses: ManageKindleAddresses(settings: settings),
        chooseTool: ChooseConverterTool(settings: settings, choice: converter),
        settings: settings, loginItem: FakeLoginItem(), converter: converter),
      covers: CoverStore(provider: FakeCoverProvider()),
      queue: SendQueueViewModel(
        sendBooks: SendBooks(
          channels: channels, preparer: FakeEPUBPreparer(),
          converter: FakeFormatConverter(isAvailable: false), staging: staging, history: history,
          retryDelay: .zero, sleep: { _ in })),
      ejector: ejector ?? self.ejector)
    panel.attach(system)
    return (panel, settings)
  }

  func denyAccess() {
    library.result = .failure(.accessDenied)
    library.canWatch = false
  }

  func grantAccess() {
    library.result = .success([.fixture(id: "a")])
    library.canWatch = true
  }

  // MARK: Routes

  @Test func reportsAFailedReloadAsANotice() async {
    let (panel, _) = makePanel()
    await panel.launch()

    library.result = .failure(.unreadable("disk I/O error"))
    await panel.library.reload()

    #expect(panel.notice == ProblemPresenter.problem(for: .unreadable("disk I/O error")))
    #expect(panel.statusItem.needsAttention)
    #expect(panel.library.state == .loaded)
  }

  @Test func opensOnTheLibraryWhenBooksCanBeRead() async {
    let (panel, _) = makePanel()
    await panel.launch()

    await panel.panelDidOpen()

    #expect(panel.route == .library)
    #expect(panel.library.state == .loaded)
    #expect(!panel.statusItem.needsAttention)
  }

  @Test func opensOnTheAccessStepWhileBooksIsOffLimits() async {
    denyAccess()
    let (panel, _) = makePanel()
    await panel.launch()

    await panel.panelDidOpen()

    #expect(panel.route == .setup)
    #expect(panel.setup.step == .libraryAccess)
    #expect(panel.statusItem.needsAttention)
  }

  @Test func asksForAccessFromTheMenuBarBeforeThePanelOpens() async {
    denyAccess()
    let (panel, _) = makePanel()

    await panel.launch()

    #expect(panel.statusItem.needsAttention)
    #expect(library.changeSubscribers == 0)
  }

  @Test func goesToTheLibraryByItselfOnceAccessIsGranted() async {
    denyAccess()
    let (panel, _) = makePanel(onSleep: { await MainActor.run { grantAccess() } })
    await panel.launch()

    await panel.panelDidOpen()

    #expect(await eventually { panel.route == .library })
    #expect(panel.library.items.count == 1)
  }

  @Test func asksForTheKindleEmailAfterAccessWhenNoneIsSetUp() async {
    denyAccess()
    let (panel, _) = makePanel(AppSettings(), onSleep: { await MainActor.run { grantAccess() } })
    await panel.launch()

    await panel.panelDidOpen()

    #expect(await eventually { panel.setup.step == .kindleEmail })
    #expect(panel.route == .setup)
  }

  @Test func movesOnWhenAccessWasGrantedWhileThePanelWasClosed() async {
    denyAccess()
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.panelDidClose()

    grantAccess()
    await panel.panelDidOpen()

    #expect(panel.route == .library)
  }

  @Test func stopsCheckingAccessWhenThePanelCloses() async {
    denyAccess()
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    #expect(panel.isWaitingForAccess)

    panel.panelDidClose()

    #expect(!panel.isWaitingForAccess)
  }

  @Test func aPanelClosedWhileOpeningWatchesNothing() async {
    denyAccess()
    let (panel, _) = makePanel()
    await panel.launch()

    let opening = Task { await panel.panelDidOpen() }
    opening.cancel()
    panel.panelDidClose()
    await opening.value

    #expect(!panel.isWaitingForAccess)
    grantAccess()
    await panel.library.reload()
    #expect(library.changeSubscribers == 0)
  }

  @Test func aLateOpeningLeavesTheReopenedPanelWatching() async {
    let (panel, _) = makePanel()
    await panel.launch()
    let gate = Signal()
    library.gate = gate

    let first = Task { await panel.panelDidOpen() }
    #expect(await eventually { library.loads == 2 })
    first.cancel()
    panel.panelDidClose()
    library.gate = nil
    // Reloads run in order, so the reopened panel's waits for the late one.
    let second = Task { await panel.panelDidOpen() }
    await gate.fire()
    await first.value
    await second.value

    #expect(library.changeSubscribers == 1)
  }

  @Test func finishingSetupShowsTheLibraryWithTheNewEmail() async {
    let (panel, settings) = makePanel(AppSettings())
    await panel.launch()
    panel.showSetup(at: .kindleEmail)
    panel.setup.form.kindleAddress = "reader@kindle.com"
    panel.setup.form.senderAddress = "me@gmail.com"
    panel.setup.form.password = "abcdefghijklmnop"

    await panel.finishSetup()

    #expect(panel.route == .library)
    #expect(await settings.settings.email == .fixture)
    #expect(panel.library.destinations == [.email(.fixture)])
  }

  @Test func aSetupThatCannotBeSavedStaysOpen() async {
    let (panel, _) = makePanel(AppSettings())
    await panel.launch()
    panel.showSetup(at: .sender)

    await panel.finishSetup()

    #expect(panel.route == .setup)
    #expect(!panel.setup.form.issues.isEmpty)
  }

  @Test func theEmailStepsCanWait() async {
    let (panel, _) = makePanel(AppSettings())
    panel.showSetup(at: .kindleEmail)

    panel.skipSetup()

    #expect(panel.route == .library)
  }

  // MARK: Escape and keys

  @Test func escapeClosesTheSheetThenClearsTheSelectionThenThePanel() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()
    await panel.openSettings(.kindle)

    panel.escape()
    #expect(!panel.isShowingSettings)
    #expect(!panel.library.selection.isEmpty)

    panel.escape()
    #expect(panel.library.selection.isEmpty)
    #expect(system.closedPanel == 0)

    panel.escape()
    #expect(system.closedPanel == 1)
  }

  @Test func keysDriveTheLibrary() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    #expect(panel.handle(KeyInput(.right)))
    #expect(panel.library.selection.ids == [BookID(rawValue: "a")])
    #expect(panel.handle(KeyInput(.character("a"), command: true)))
    #expect(panel.library.selection.count == 2)
    #expect(panel.handle(KeyInput(.character("2"), command: true)))
    #expect(await eventually { panel.library.layout == .list })
    #expect(panel.handle(KeyInput(.character("f"), command: true)))
    #expect(panel.searchFocusRequests == 1)
    #expect(panel.handle(KeyInput(.character(","), command: true)))
    #expect(await eventually { panel.isShowingSettings })
    #expect(panel.settings.section == nil)
  }

  @Test func libraryKeysWaitWhileSomethingCoversTheLibrary() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    await panel.openSettings(.kindle)
    #expect(!panel.handle(KeyInput(.down)))

    panel.closeSettings()
    panel.showSetup(at: .kindleEmail)
    #expect(!panel.handle(KeyInput(.character("a"), command: true)))
    #expect(!panel.handle(KeyInput(.character("q"), command: true)))
  }

  @Test func upAndDownLeaveTheSearchFieldForTheLibrary() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    #expect(panel.handle(KeyInput(.down, isEditingText: true)))
    #expect(panel.library.selection.ids == [BookID(rawValue: "a")])
    #expect(system.endedEditing == 1)
    #expect(!panel.handle(KeyInput(.left, isEditingText: true)))
    #expect(!panel.handle(KeyInput(.character("a"), command: true, isEditingText: true)))

    await panel.openSettings(.kindle)
    #expect(!panel.handle(KeyInput(.down, isEditingText: true)))
  }

  @Test func clickingABookTakesTheKeyboardBackFromSearch() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    panel.click(BookID(rawValue: "a"), .plain)

    #expect(system.endedEditing == 1)
    #expect(panel.library.selection.ids == [BookID(rawValue: "a")])
  }

  @Test func commandCommaLeavesAnOpenSheetAsItIs() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.openSettings(.sender)
    panel.settings.form.password = "typed"

    #expect(panel.handle(KeyInput(.character(","), command: true)))
    try? await Task.sleep(for: .milliseconds(100))

    #expect(panel.settings.section == .sender)
    #expect(panel.settings.form.password == "typed")
  }

  @Test func escapeClearsTheSearchBeforeTheSelection() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()
    panel.library.query = "moby"

    panel.escape()

    #expect(panel.library.query.isEmpty)
    #expect(!panel.library.selection.isEmpty)
  }

  @Test func escapeLeavesASetupThatCanWait() async {
    let (panel, _) = makePanel(AppSettings())
    await panel.launch()
    await panel.panelDidOpen()
    panel.showSetup(at: .kindleEmail)

    panel.escape()

    #expect(panel.route == .library)
    #expect(system.closedPanel == 0)
  }

  @Test func escapeOnTheAccessStepClosesThePanel() async {
    denyAccess()
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    panel.escape()

    #expect(panel.route == .setup)
    #expect(system.closedPanel == 1)
  }

  @Test func returnDoesWhatTheScreenIsFor() async {
    let (panel, settings) = makePanel(AppSettings())
    await panel.launch()
    await panel.panelDidOpen()
    panel.showSetup(at: .kindleEmail)
    panel.setup.form.kindleAddress = "reader@kindle.com"

    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(panel.setup.step == .sender)

    panel.setup.form.senderAddress = "me@gmail.com"
    panel.setup.form.password = "abcdefghijklmnop"
    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(await eventually { panel.route == .library })
    #expect(await settings.settings.email == .fixture)

    await panel.openSettings(.kindle)
    panel.settings.form.kindleAddress = "other@kindle.com"
    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(await eventually { !panel.isShowingSettings })
    #expect(await settings.settings.email?.kindleAddress.rawValue == "other@kindle.com")
  }

  @Test func returnLeavesTheKeyAloneWithNothingToSend() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    #expect(!panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(panel.route == .library)
  }

  // MARK: Sending

  @Test func sendsTheSelectionToTheActiveDestination() async {
    let channel = FakeDeliveryChannel()
    let (panel, _) = makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(panel.route == .queue)
    #expect(panel.queue.rows.map(\.id.rawValue) == ["a", "b"])
    #expect(panel.queue.destination == .email(.fixture))
    #expect(panel.library.selection.isEmpty)
    await panel.queue.waitUntilFinished()
    #expect(channel.deliveries.count == 2)
    #expect(panel.library.items.map(\.tone) == [.sent, .sent])
  }

  @Test func quickSendSendsOneBook() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    panel.quickSend(BookID(rawValue: "b"))

    #expect(panel.route == .queue)
    #expect(panel.queue.rows.map(\.id.rawValue) == ["b"])
  }

  @Test func sendsNothingUntilThereIsADestination() async {
    let (panel, _) = makePanel(AppSettings())
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    #expect(!panel.library.canSend)
    #expect(panel.library.sendHint == "Set up your Kindle email first")
    #expect(!panel.handle(KeyInput(.returnKey)))
    panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
  }

  @Test func theMenuBarShowsTheBookBeingSent() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    panel.sendSelection()
    await channel.waitUntilDeliveryStarts()

    #expect(panel.statusItem.progress == "↑ 1/2")
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.statusItem.progress == nil)
  }

  @Test func aRunningQueueStaysWhenEscapeClosesThePanel() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    panel.quickSend(BookID(rawValue: "a"))
    await channel.waitUntilDeliveryStarts()

    panel.escape()
    panel.panelDidClose()
    await panel.panelDidOpen()

    #expect(system.closedPanel == 1)
    #expect(panel.route == .queue)
    #expect(panel.queue.isRunning)
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
  }

  @Test func aFinishedQueueGoesBackToTheLibrary() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    panel.escape()

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
  }

  @Test func aFailedSendNeedsAttentionUntilTheQueueIsCleared() async {
    let (panel, _) = makePanel(channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    await panel.launch()
    await panel.panelDidOpen()
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()
    #expect(panel.statusItem.needsAttention)

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(panel.route == .library)
    #expect(!panel.statusItem.needsAttention)
  }

  @Test func theToastsRetrySendsTheFailedBooksAgain() async {
    let unreachable = SendFailure.connectionFailed(host: "smtp.gmail.com")
    let (panel, _) = makePanel(
      channel: FakeDeliveryChannel(.fail(unreachable), .fail(unreachable), .succeed))
    await panel.launch()
    await panel.panelDidOpen()
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()
    #expect(panel.queue.summary?.fix?.action == .retry)

    await panel.performQueueFix()
    await panel.queue.waitUntilFinished()

    #expect(panel.queue.rows.map(\.status) == [.sent])
    #expect(panel.route == .queue)
  }

  @Test func theToastsSettingsFixOpensOverTheQueue() async {
    let (panel, _) = makePanel(channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    await panel.launch()
    await panel.panelDidOpen()
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    await panel.performQueueFix()

    #expect(panel.isShowingSettings)
    #expect(panel.settings.section == .sender)
    #expect(panel.route == .queue)
  }

  @Test func theToastsEjectFixEjectsTheKindleFromTheLibrary() async {
    let kindle = KindleVolume.fixture()
    library.result = .success([.fixture(id: "a", format: .pdf)])
    monitor.update([kindle])
    let (panel, _) = makePanel(AppSettings(email: .fixture, activeDestination: .usb))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    await panel.performQueueFix()

    #expect(ejector.ejected == [kindle])
    #expect(panel.route == .library)
  }

  @Test func aBookTooLargeToEmailCanGoOverUSBInstead() async {
    let tooLarge = SendFailure.tooLarge(bytes: 62_000_000, limit: FormatPolicy.emailSizeLimit)
    monitor.update([.fixture()])
    let (panel, _) = makePanel(channel: FakeDeliveryChannel(.fail(tooLarge)))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.isKindlePluggedIn })
    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    await panel.performQueueFix()

    #expect(panel.route == .library)
    #expect(panel.library.preferredDestination == .usb)
  }

  // MARK: Settings sheet

  @Test func aJumpBarChosenInSettingsReachesTheLibrary() async {
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.openSettings(.general)

    await panel.settings.setJumpBar(.compact)

    #expect(panel.library.jumpBar == .compact)
  }

  @Test func aTestEmailThatSavedANewSetupShowsItsChip() async {
    let (panel, _) = makePanel(AppSettings())
    await panel.launch()
    await panel.openSettings(.sender)
    let form = panel.settings.form
    form.kindleAddress = "reader@kindle.com"
    form.senderAddress = "me@gmail.com"
    form.password = "abcdefghijklmnop"

    await panel.sendTest(from: form)

    #expect(panel.library.hasKindleEmail)
    #expect(panel.library.destinations == [.email(.fixture)])
  }

  @Test func savingSettingsUpdatesTheDestinations() async {
    let (panel, _) = makePanel(AppSettings())
    await panel.launch()
    await panel.openSettings(.kindle)
    panel.settings.form.kindleAddress = "reader@kindle.com"
    panel.settings.form.senderAddress = "me@gmail.com"
    panel.settings.form.password = "abcdefghijklmnop"

    await panel.saveSettings()

    #expect(!panel.isShowingSettings)
    #expect(panel.library.destinations == [.email(.fixture)])
  }

  // MARK: Fixes, notices and the status item

  @Test func runsEachFixWhereItBelongs() async throws {
    monitor.update([.fixture()])
    let (panel, _) = makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.isKindlePluggedIn })
    let link = try #require(URL(string: "https://www.amazon.com/mycd"))
    let loads = library.loads

    await panel.perform(.openPrivacySettings)
    await panel.perform(.openURL(link))
    #expect(
      system.opened.map(\.absoluteString) == [PanelModel.fullDiskAccessURL, link.absoluteString])

    await panel.perform(.openSettings(.sender))
    #expect(panel.isShowingSettings)
    #expect(panel.settings.section == .sender)

    await panel.perform(.useDestination(.usb))
    #expect(panel.library.preferredDestination == .usb)

    await panel.perform(.retry)
    #expect(library.loads == loads + 1)

    await panel.perform(.eject(.fixture()))
    #expect(ejector.ejected == [.fixture()])
  }

  @Test func aNoticeNeedsAttentionUntilItsFixRuns() async {
    let (panel, _) = makePanel()
    await panel.launch()
    let notice = ProblemPresenter.settingsSetAside(URL(filePath: "/tmp/settings.corrupt-1.json"))

    panel.show(notice: notice)
    #expect(panel.notice == notice)
    #expect(panel.statusItem.needsAttention)

    await panel.performNoticeFix()

    #expect(panel.notice == nil)
    #expect(panel.isShowingSettings)
    #expect(!panel.statusItem.needsAttention)
  }

  @Test func theMenuBarIconFillsWhileAKindleIsPluggedIn() async {
    let (panel, _) = makePanel()
    await panel.launch()
    #expect(panel.statusItem.symbolName == "book.closed")

    monitor.update([.fixture()])

    #expect(await eventually { panel.statusItem.symbolName == "book.closed.fill" })
  }

  // MARK: Ejecting

  @Test func ejectsAPluggedInKindle() async {
    monitor.update([.fixture()])
    let (panel, _) = makePanel()
    await panel.launch()
    #expect(await eventually { panel.library.isKindlePluggedIn })

    await panel.eject(.fixture())

    #expect(ejector.ejected == [.fixture()])
    #expect(panel.ejecting == nil)
    #expect(panel.notice == nil)
  }

  @Test func ejectingAKindleThatIsGoneDoesNothing() async {
    let (panel, _) = makePanel()
    await panel.launch()

    await panel.eject(.fixture())

    #expect(ejector.ejected.isEmpty)
    #expect(panel.notice == nil)
  }

  @Test func explainsAKindleThatWontEject() async {
    ejector.fail(with: .inUse)
    monitor.update([.fixture()])
    let (panel, _) = makePanel()
    await panel.launch()
    #expect(await eventually { panel.library.isKindlePluggedIn })

    await panel.eject(.fixture())

    #expect(panel.notice?.title == "Kindle is in use")
    #expect(panel.notice?.fix?.action == .eject(.fixture()))
  }

  @Test func keepsAKindleWhileABookIsCopiedToIt() async {
    let kindle = KindleVolume.fixture()
    library.result = .success([.fixture(id: "a", format: .pdf)])
    monitor.update([kindle])
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    panel.quickSend(BookID(rawValue: "a"))
    await channel.waitUntilDeliveryStarts()

    #expect(!panel.canEject(kindle))
    await panel.eject(kindle)
    #expect(ejector.ejected.isEmpty)

    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.canEject(kindle))
  }

  @Test func anEjectBlockedByACopySaysSo() async {
    let kindle = KindleVolume.fixture()
    library.result = .success([.fixture(id: "a", format: .pdf)])
    monitor.update([kindle])
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    panel.quickSend(BookID(rawValue: "a"))
    await channel.waitUntilDeliveryStarts()

    await panel.eject(kindle)

    #expect(ejector.ejected.isEmpty)
    #expect(panel.notice?.title == "Kindle is still being copied to")
    #expect(panel.notice?.fix?.action == .eject(kindle))

    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
  }

  @Test func doesNotSendToAKindleBeingEjected() async {
    let kindle = KindleVolume.fixture()
    library.result = .success([.fixture(id: "a", format: .pdf)])
    monitor.update([kindle])
    let gate = Signal()
    let (panel, _) = makePanel(
      AppSettings(email: .fixture, activeDestination: .usb),
      ejector: FakeKindleEjector(gate: gate))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    let ejecting = Task { await panel.eject(kindle) }
    #expect(await eventually { panel.ejecting == kindle })

    panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
    await gate.fire()
    await ejecting.value
  }

  @Test func showsSendleInFinderForTheFullDiskAccessList() {
    let (panel, _) = makePanel()

    panel.revealApp()

    #expect(system.revealedApp == 1)
  }
}
