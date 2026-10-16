import Foundation
import Observation
import SendleDomain

package enum SetupStep: Int, CaseIterable, Sendable {
  case libraryAccess
  case kindleEmail
  case sender
}

/// The first-run flow: library access, then the Kindle address, then the sender.
@Observable @MainActor
public final class SetupViewModel {
  package private(set) var step = SetupStep.libraryAccess
  package let form: EmailForm

  private let checkAccess: @MainActor () async -> Bool
  private let sleep: @Sendable (Duration) async -> Void

  /// `checkAccess` reloads the library and tells whether Books could be read.
  public init(
    configure: ConfigureEmail,
    checkAccess: @escaping @MainActor () async -> Bool,
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    form = EmailForm(configure: configure)
    self.checkAccess = checkAccess
    self.sleep = sleep
  }

  package var stepLabel: String {
    "Step \(step.rawValue + 1) of \(SetupStep.allCases.count)"
  }

  package func begin(at step: SetupStep) {
    self.step = step
  }

  /// Checks every 2 s while the access step shows. False when cancelled before access arrived.
  package func waitForLibraryAccess() async -> Bool {
    while !Task.isCancelled {
      if await checkAccess() { return true }
      await sleep(.seconds(2))
    }
    return false
  }

  /// True when nothing is left to set up.
  package func accessGranted(emailConfigured: Bool) -> Bool {
    guard !emailConfigured else { return true }
    step = .kindleEmail
    return false
  }

  package func continueToSender() {
    if form.checkKindleAddress() { step = .sender }
  }

  package func back() {
    if step == .sender { step = .kindleEmail }
  }

  package func finish() async -> Bool {
    await form.save()
  }
}
