import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SetupViewModelTests {
  let settings = InMemorySettingsStore()
  let sleeps = Recorder<Duration>()

  func makeSetup(
    checkAccess: @escaping @MainActor () async -> Bool = { true },
    sleep: (@Sendable (Duration) async -> Void)? = nil
  ) -> SetupViewModel {
    let sleeps = sleeps
    return SetupViewModel(
      configure: ConfigureEmail(settings: settings, secrets: MemorySecretStore()),
      sendTest: SendTestEmail(
        settings: settings, channels: FakeDeliveryChannelFactory(), staging: FakeStagingArea()),
      checkAccess: checkAccess,
      sleep: sleep ?? { await sleeps.record($0) })
  }

  @Test func checksForLibraryAccessEveryTwoSeconds() async {
    var answers = [false, false, true]
    let setup = makeSetup(checkAccess: { answers.removeFirst() })

    #expect(await setup.waitForLibraryAccess())
    #expect(await sleeps.values == [.seconds(2), .seconds(2)])
  }

  @Test func stopsCheckingWhenCancelled() async {
    let setup = makeSetup(checkAccess: { false }, sleep: { try? await Task.sleep(for: $0) })

    let waiting = Task { await setup.waitForLibraryAccess() }
    waiting.cancel()

    #expect(await waiting.value == false)
  }

  @Test func finishesAtOnceWhenEmailIsAlreadySetUp() {
    let setup = makeSetup()
    setup.begin(at: .libraryAccess)

    #expect(setup.accessGranted(emailConfigured: true))
  }

  @Test func asksForTheKindleEmailOnceAccessArrives() {
    let setup = makeSetup()
    setup.begin(at: .libraryAccess)

    #expect(!setup.accessGranted(emailConfigured: false))
    #expect(setup.step == .kindleEmail)
    #expect(setup.stepLabel == "Step 2 of 3")
  }

  @Test func needsAKindleAddressBeforeTheSenderStep() {
    let setup = makeSetup()
    setup.begin(at: .kindleEmail)

    setup.form.kindleAddress = "reader"
    setup.continueToSender()
    #expect(setup.step == .kindleEmail)

    setup.form.kindleAddress = "reader@kindle.com"
    setup.continueToSender()
    #expect(setup.step == .sender)

    setup.back()
    #expect(setup.step == .kindleEmail)
  }

  @Test func finishingSavesTheEmailSetup() async {
    let setup = makeSetup()
    setup.begin(at: .kindleEmail)
    setup.form.kindleAddress = "reader@kindle.com"
    setup.form.senderAddress = "me@gmail.com"
    setup.form.password = "abcdefghijklmnop"

    #expect(await setup.finish())
    #expect(await settings.settings.email == .fixture)
  }
}
