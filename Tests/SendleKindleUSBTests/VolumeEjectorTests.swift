import Foundation
import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

struct VolumeEjectorTests {
  @Test func aBusyVolumeIsInUse() {
    let busy = NSError(domain: NSOSStatusErrorDomain, code: -47)

    #expect(VolumeEjector.failure(busy) == .inUse)
  }

  @Test func passesOnOtherFailures() {
    let gone = NSError(
      domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "No such volume"])

    #expect(VolumeEjector.failure(gone) == .failed("No such volume"))
  }

  @Test func logsAnEject() async throws {
    let log = FakeActivityLog()

    try await VolumeEjector(unmount: { _ in }, log: log).eject(.fixture(name: "Paperwhite"))

    #expect(log.summary == ["info USB Ejected Paperwhite"])
  }

  @Test func logsWhyAnEjectFailed() async {
    let log = FakeActivityLog()
    let ejector = VolumeEjector(
      unmount: { _ in throw NSError(domain: NSOSStatusErrorDomain, code: -47) }, log: log)

    await #expect(throws: EjectError.inUse) {
      try await ejector.eject(.fixture(name: "Paperwhite"))
    }

    #expect(log.summary == ["warning USB Couldn't eject Paperwhite: something is still open on it"])
  }
}
