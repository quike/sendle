import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PanelModelTests {
  let harness = PanelHarness()
  var library: FakeBooksLibrary { harness.library }
  var monitor: FakeDestinationMonitor { harness.monitor }
  var system: FakeSystemActions { harness.system }
  var ejector: FakeKindleEjector { harness.ejector }
  var log: FakeActivityLog { harness.log }

  // MARK: Routes

  @Test func reportsAFailedReloadAsANotice() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()

    library.result = .failure(.unreadable("disk I/O error"))
    await panel.library.reload()

    #expect(panel.notice == ProblemPresenter.problem(for: .unreadable("disk I/O error")))
    #expect(panel.statusItem.needsAttention)
    #expect(panel.library.state == .loaded)
  }

  @Test func opensOnTheLibraryWhenBooksCanBeRead() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()

    await panel.panelDidOpen()

    #expect(panel.route == .library)
    #expect(panel.library.state == .loaded)
    #expect(!panel.statusItem.needsAttention)
  }

  @Test func opensOnTheAccessStepWhileBooksIsOffLimits() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()
    await panel.launch()

    await panel.panelDidOpen()

    #expect(panel.route == .setup)
    #expect(panel.setup.step == .libraryAccess)
    #expect(panel.statusItem.needsAttention)
  }

  @Test func asksForAccessFromTheMenuBarBeforeThePanelOpens() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()

    await panel.launch()

    #expect(panel.statusItem.needsAttention)
    #expect(library.changeSubscribers == 0)
  }

  @Test func goesToTheLibraryByItselfOnceAccessIsGranted() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel(onSleep: { await MainActor.run { harness.grantAccess() } })
    await panel.launch()

    await panel.panelDidOpen()

    #expect(await eventually { panel.route == .library })
    #expect(panel.library.items.count == 1)
  }

  @Test func asksForTheKindleEmailAfterAccessWhenNoneIsSetUp() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel(
      AppSettings(), onSleep: { await MainActor.run { harness.grantAccess() } })
    await panel.launch()

    await panel.panelDidOpen()

    #expect(await eventually { panel.setup.step == .kindleEmail })
    #expect(panel.route == .setup)
  }

  @Test func movesOnWhenAccessWasGrantedWhileThePanelWasClosed() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.panelDidClose()

    harness.grantAccess()
    await panel.panelDidOpen()

    #expect(panel.route == .library)
  }

  @Test func stopsCheckingAccessWhenThePanelCloses() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    #expect(panel.isWaitingForAccess)

    panel.panelDidClose()

    #expect(!panel.isWaitingForAccess)
  }

  @Test func aPanelClosedWhileOpeningWatchesNothing() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()
    await panel.launch()

    let opening = Task { await panel.panelDidOpen() }
    opening.cancel()
    panel.panelDidClose()
    await opening.value

    #expect(!panel.isWaitingForAccess)
    harness.grantAccess()
    await panel.library.reload()
    #expect(library.changeSubscribers == 0)
  }

  @Test func aLateOpeningLeavesTheReopenedPanelWatching() async {
    let (panel, _) = harness.makePanel()
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
    let (panel, settings) = harness.makePanel(AppSettings())
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
    let (panel, _) = harness.makePanel(AppSettings())
    await panel.launch()
    panel.showSetup(at: .sender)

    await panel.finishSetup()

    #expect(panel.route == .setup)
    #expect(!panel.setup.form.issues.isEmpty)
  }

  @Test func theEmailStepsCanWait() async {
    let (panel, _) = harness.makePanel(AppSettings())
    panel.showSetup(at: .kindleEmail)

    panel.skipSetup()

    #expect(panel.route == .library)
  }

  // MARK: Escape and keys

  @Test func escapeClosesTheSheetThenClearsTheSelectionThenThePanel() async {
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    panel.click(BookID(rawValue: "a"), .plain)

    #expect(system.endedEditing == 1)
    #expect(panel.library.selection.ids == [BookID(rawValue: "a")])
  }

  @Test func commandCommaLeavesAnOpenSheetAsItIs() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.openSettings(.sender)
    panel.settings.form.password = "typed"

    #expect(panel.handle(KeyInput(.character(","), command: true)))
    try? await Task.sleep(for: .milliseconds(100))

    #expect(panel.settings.section == .sender)
    #expect(panel.settings.form.password == "typed")
  }

  @Test func escapeClearsTheSearchBeforeTheSelection() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()
    panel.library.query = "moby"

    panel.escape()

    #expect(panel.library.query.isEmpty)
    #expect(!panel.library.selection.isEmpty)
  }

  @Test func escapeLeavesASetupThatCanWait() async {
    let (panel, _) = harness.makePanel(AppSettings())
    await panel.launch()
    await panel.panelDidOpen()
    panel.showSetup(at: .kindleEmail)

    panel.escape()

    #expect(panel.route == .library)
    #expect(system.closedPanel == 0)
  }

  @Test func escapeOnTheAccessStepClosesThePanel() async {
    harness.denyAccess()
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    panel.escape()

    #expect(panel.route == .setup)
    #expect(system.closedPanel == 1)
  }

  @Test func returnDoesWhatTheScreenIsFor() async {
    let (panel, settings) = harness.makePanel(AppSettings())
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
    panel.settings.newKindleAddress = "other@kindle.com"
    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(await eventually { panel.settings.activeKindleAddress?.rawValue == "other@kindle.com" })
    #expect(panel.isShowingSettings)
    #expect(await settings.settings.email?.kindleAddress.rawValue == "other@kindle.com")
  }

  @Test func returnInSettingsDoesWhatThePageIsFor() async {
    let (panel, settings) = harness.makePanel()
    await panel.launch()

    await panel.openSettings()
    panel.settings.query = "pass"
    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(panel.settings.section == .sender)

    panel.settings.form.senderAddress = "new@gmail.com"
    panel.settings.form.password = "abcdefghijklmnop"
    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(await eventually { !panel.isShowingSettings })
    #expect(await settings.settings.email?.senderAddress == "new@gmail.com")

    await panel.openSettings(.general)
    #expect(!panel.handle(KeyInput(.returnKey)))
    await panel.openSettings(.kindle)
    #expect(!panel.handle(KeyInput(.returnKey)))
    await panel.openSettings()
    #expect(!panel.handle(KeyInput(.returnKey)))
    #expect(panel.isShowingSettings)
  }

  @Test func returnLeavesTheKeyAloneWithNothingToSend() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    #expect(!panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(panel.route == .library)
  }

  // MARK: Sending

  @Test func sendsTheSelectionToTheActiveDestination() async {
    let channel = FakeDeliveryChannel()
    let (panel, _) = harness.makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(await eventually { panel.route == .queue })
    #expect(panel.queue.rows.map(\.id.rawValue) == ["a", "b"])
    #expect(panel.queue.destination == .email(.fixture))
    #expect(panel.library.selection.isEmpty)
    await panel.queue.waitUntilFinished()
    #expect(channel.deliveries.count == 2)
    #expect(panel.library.items.map(\.tone) == [.sent, .sent])
  }

  @Test func quickSendSendsOneBook() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()

    await panel.quickSend(BookID(rawValue: "b"))

    #expect(panel.route == .queue)
    #expect(panel.queue.rows.map(\.id.rawValue) == ["b"])
  }

  @Test func sendsNothingUntilThereIsADestination() async {
    let (panel, _) = harness.makePanel(AppSettings())
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    #expect(!panel.library.canSend)
    #expect(panel.library.sendHint == "Set up your Kindle email first")
    #expect(!panel.handle(KeyInput(.returnKey)))
    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
  }

  @Test func theMenuBarShowsTheBookBeingSent() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = harness.makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    await panel.sendSelection()
    await channel.waitUntilDeliveryStarts()

    #expect(panel.statusItem.progress == "↑ 1/2")
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.statusItem.progress == nil)
  }

  @Test func aRunningQueueStaysWhenEscapeClosesThePanel() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = harness.makePanel(channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    await panel.quickSend(BookID(rawValue: "a"))
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
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    panel.escape()

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
  }

  @Test func aFailedSendNeedsAttentionUntilTheQueueIsCleared() async {
    let (panel, _) = harness.makePanel(
      channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    await panel.launch()
    await panel.panelDidOpen()
    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()
    #expect(panel.statusItem.needsAttention)

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(panel.route == .library)
    #expect(!panel.statusItem.needsAttention)
  }

  @Test func theToastsRetrySendsTheFailedBooksAgain() async {
    let unreachable = SendFailure.connectionFailed(host: "smtp.gmail.com")
    let (panel, _) = harness.makePanel(
      channel: FakeDeliveryChannel(.fail(unreachable), .fail(unreachable), .succeed))
    await panel.launch()
    await panel.panelDidOpen()
    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()
    #expect(panel.queue.summary?.fix?.action == .retry)

    await panel.performQueueFix()
    await panel.queue.waitUntilFinished()

    #expect(panel.queue.rows.map(\.status) == [.sent])
    #expect(panel.route == .queue)
  }

  @Test func theToastsSettingsFixOpensOverTheQueue() async {
    let (panel, _) = harness.makePanel(
      channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    await panel.launch()
    await panel.panelDidOpen()
    await panel.quickSend(BookID(rawValue: "a"))
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
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, activeDestination: .usb))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    await panel.performQueueFix()

    #expect(ejector.ejected == [kindle])
    #expect(panel.route == .library)
  }

  @Test func aBookTooLargeToEmailCanGoOverUSBInstead() async {
    let tooLarge = SendFailure.tooLarge(bytes: 62_000_000, limit: FormatPolicy.emailSizeLimit)
    monitor.update([.fixture()])
    let (panel, _) = harness.makePanel(channel: FakeDeliveryChannel(.fail(tooLarge)))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.isKindlePluggedIn })
    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    await panel.performQueueFix()

    #expect(panel.route == .library)
    #expect(panel.library.preferredDestination == .usb)
  }

  // MARK: Logs

  @Test func theLogsButtonFollowsTheSetting() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    #expect(!panel.showsLogs)

    await panel.settings.setShowsLogs(true)

    #expect(panel.showsLogs)
  }

  @Test func opensTheLogsAndGoesBackWhereItWas() async {
    let (panel, _) = harness.makePanel()
    log.info(.library, "Read 2 books")

    panel.openLogs()
    #expect(panel.route == .logs)
    #expect(panel.logs.visible.map(\.message) == ["Read 2 books"])

    panel.escape()
    #expect(panel.route == .library)
  }

  @Test func aFailedBookOpensItsStory() async {
    let (panel, _) = harness.makePanel()
    log.heading(.book(BookID(rawValue: "a")), .mail, "Moby-Dick · reader@kindle.com")
    log.error(.mail, "S: 553 Sender address rejected")

    panel.openLogs(revealing: .book(BookID(rawValue: "a")))

    #expect(panel.logs.scrollTarget == 1)
    #expect(!panel.logs.isAtBottom)
  }

  @Test func theLogsButtonOpensAtTheNewestLines() async {
    let (panel, _) = harness.makePanel()
    log.heading(.book(BookID(rawValue: "a")), .mail, "Moby-Dick · reader@kindle.com")
    panel.openLogs(revealing: .book(BookID(rawValue: "a")))
    panel.escape()

    panel.openLogs()

    #expect(panel.logs.scrollTarget == nil)
    #expect(panel.logs.isAtBottom)
  }

  @Test func aTestThatFailedInSettingsOpensItsLogsOverTheSheet() async {
    let (panel, _) = harness.makePanel()
    await panel.openSettings(.sender)
    log.heading(.sendTest, .mail, "Send test · reader@kindle.com")

    panel.openLogs(revealing: .sendTest)

    #expect(!panel.isShowingSettings)
    #expect(panel.route == .logs)
    #expect(panel.logs.scrollTarget == 1)
  }

  @Test func backFromTheLogsReturnsToTheSettingsTheyWereOpenedFrom() async {
    let (panel, _) = harness.makePanel(
      channel: FakeDeliveryChannel(.fail(.authenticationFailed(.gmail))))
    await panel.openSettings(.sender)
    panel.settings.form.password = "abcdefghijklmnop"
    await panel.sendTest(from: panel.settings.form)
    let result = panel.settings.form.testStatus
    panel.openLogs(revealing: .sendTest)

    panel.escape()

    #expect(panel.route == .library)
    #expect(panel.isShowingSettings)
    #expect(panel.settings.section == .sender)
    #expect(panel.settings.form.testStatus == result)
    #expect(result != .idle)
  }

  @Test func copiesWhatTheLogsShow() async {
    let (panel, _) = harness.makePanel()
    log.info(.library, "Read 2 books")
    panel.openLogs()

    panel.copyLogs()

    #expect(system.copied == [panel.logs.copyText()])
  }

  // MARK: Settings sheet

  @Test func choosesBokoThroughTheSystemsFilePicker() async {
    let (panel, settings) = harness.makePanel()
    await panel.openSettings(.usb)

    await panel.chooseBoko()
    #expect(await settings.settings.bokoPath == nil)

    system.program = URL(filePath: "/Users/reader/bin/boko")
    await panel.chooseBoko()
    #expect(await settings.settings.bokoPath == "/Users/reader/bin/boko")
  }

  @Test func aBokoChosenInSettingsLetsEPUBsGoOverUSBAtOnce() async {
    monitor.update([.fixture()])
    let (panel, _) = harness.makePanel()
    await panel.launch()
    #expect(await eventually { panel.library.isKindlePluggedIn })
    await panel.library.activate(.usb)
    await panel.openSettings(.usb)
    #expect(panel.library.items.first?.canSend == false)

    system.program = URL(filePath: "/Users/reader/bin/boko")
    await panel.chooseBoko()
    #expect(panel.library.items.first?.canSend == true)

    await panel.settings.resetBoko()
    #expect(panel.library.items.first?.canSend == false)
  }

  @Test func aJumpBarChosenInSettingsReachesTheLibrary() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.openSettings(.general)

    await panel.settings.setJumpBar(.compact)

    #expect(panel.library.jumpBar == .compact)
  }

  // MARK: Floating controls

  @Test func attachedControlsKeepTheSendBarAndTheAZBarInTheCard() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.panelDidOpen()
    #expect(!panel.showsSendBar)
    #expect(panel.sendBarRoom == 0)

    panel.library.selectAll()

    #expect(panel.showsSendBar)
    #expect(!panel.showsSendCard)
    #expect(panel.sendBarRoom == 64)
    #expect(panel.floatingRailSide == nil)
    #expect(!panel.showsFloatingRail)
    #expect(panel.windowMargins == PanelView.margins)
  }

  @Test func floatingControlsPutTheSendBarOnItsOwnCardWithTheSelection() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, controls: .floating))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(!panel.showsSendCard)

    panel.library.selectAll()

    #expect(panel.showsSendCard)
    #expect(!panel.showsSendBar)
    #expect(panel.sendBarRoom == 0)
    _ = panel.library.clearSelection()
    #expect(!panel.showsSendCard)
  }

  @Test func theFloatingAZCardTakesTheSideThePanelWasPlacedFor() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, controls: .floating))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(panel.floatingRailSide == .trailing)
    #expect(panel.showsFloatingRail)
    #expect(panel.windowMargins == FloatingControls.margins(.floating, side: .trailing))

    panel.railSide = .leading

    #expect(panel.floatingRailSide == .leading)
    #expect(panel.windowMargins == FloatingControls.margins(.floating, side: .leading))
  }

  /// The floating cards belong to the books, so a sheet over them or another screen hides them.
  @Test func theFloatingCardsHideBehindSettingsAndOtherScreens() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, controls: .floating))
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    await panel.openSettings()
    #expect(!panel.showsSendCard)
    #expect(!panel.showsFloatingRail)
    #expect(panel.floatingRailSide == .trailing)

    panel.closeSettings()
    #expect(panel.showsSendCard)
    #expect(panel.showsFloatingRail)

    panel.openLogs()
    #expect(!panel.showsSendCard)
    #expect(!panel.showsFloatingRail)
  }

  @Test func returnSendsAndEscapeClearsWithFloatingControls() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, controls: .floating))
    await panel.launch()
    await panel.panelDidOpen()
    panel.library.selectAll()

    #expect(panel.handle(KeyInput(.escape)))
    #expect(panel.library.selection.isEmpty)
    #expect(!panel.showsSendCard)

    panel.library.selectAll()
    #expect(panel.handle(KeyInput(.returnKey)))
    #expect(await eventually { panel.route == .queue })
    #expect(!panel.showsSendCard)
  }

  @Test func aControlsStyleChosenInSettingsReachesThePanel() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.openSettings(.general)

    await panel.settings.setControls(.floating)

    #expect(panel.controls == .floating)
  }

  @Test func aTestEmailThatSavedANewSetupShowsItsChip() async {
    let (panel, _) = harness.makePanel(AppSettings())
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

  @Test func aTestEmailUpdatesTheSenderSummary() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.openSettings(.sender)
    let form = panel.settings.form
    form.provider = .fastmail
    form.senderAddress = "me@fastmail.com"
    form.password = "abcdefghijklmnop"

    await panel.sendTest(from: form)
    panel.settings.show(nil)

    #expect(panel.settings.summary(of: .sender) == "Fastmail · me@fastmail.com")
  }

  @Test func savingSettingsUpdatesTheDestinations() async {
    let (panel, _) = harness.makePanel(AppSettings())
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
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel()
    await panel.launch()
    #expect(panel.statusItem.symbolName == "book.closed")

    monitor.update([.fixture()])

    #expect(await eventually { panel.statusItem.symbolName == "book.closed.fill" })
  }

  // MARK: Ejecting

  @Test func ejectsAPluggedInKindle() async {
    monitor.update([.fixture()])
    let (panel, _) = harness.makePanel()
    await panel.launch()
    #expect(await eventually { panel.library.isKindlePluggedIn })

    await panel.eject(.fixture())

    #expect(ejector.ejected == [.fixture()])
    #expect(panel.ejecting == nil)
    #expect(panel.notice == nil)
  }

  @Test func ejectingAKindleThatIsGoneDoesNothing() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()

    await panel.eject(.fixture())

    #expect(ejector.ejected.isEmpty)
    #expect(panel.notice == nil)
  }

  @Test func explainsAKindleThatWontEject() async {
    ejector.fail(with: .inUse)
    monitor.update([.fixture()])
    let (panel, _) = harness.makePanel()
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
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    await panel.quickSend(BookID(rawValue: "a"))
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
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel)
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    await panel.quickSend(BookID(rawValue: "a"))
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
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb),
      ejector: FakeKindleEjector(gate: gate))
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    let ejecting = Task { await panel.eject(kindle) }
    #expect(await eventually { panel.ejecting == kindle })

    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.route == .library)
    #expect(panel.queue.isEmpty)
    await gate.fire()
    await ejecting.value
  }

  @Test func showsSendleInFinderForTheFullDiskAccessList() {
    let (panel, _) = harness.makePanel()

    panel.revealApp()

    #expect(system.revealedApp == 1)
  }
}
