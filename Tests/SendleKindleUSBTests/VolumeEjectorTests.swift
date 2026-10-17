import Foundation
import SendleDomain
import SendleKindleUSB
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
}
