import AppKit
import SendleDomain

/// Unmounts a Kindle and ejects its drive, as Finder's Eject does.
public struct VolumeEjector: KindleEjector {
  public init() {}

  public func eject(_ volume: KindleVolume) async throws(EjectError) {
    do {
      try NSWorkspace.shared.unmountAndEjectDevice(at: volume.mountURL)
    } catch {
      throw Self.failure(error as NSError)
    }
  }

  /// A busy volume (`fBsyErr`) is the one failure the user can fix, by closing what's open on it.
  package static func failure(_ error: NSError) -> EjectError {
    error.domain == NSOSStatusErrorDomain && error.code == -47
      ? .inUse : .failed(error.localizedDescription)
  }
}
