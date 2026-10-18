import AppKit
import SendleDomain

/// Unmounts a Kindle and ejects its drive, as Finder's Eject does.
public struct VolumeEjector: KindleEjector {
  package typealias Unmount = @Sendable (URL) throws -> Void

  private let unmount: Unmount
  private let log: any ActivityLog

  public init(log: any ActivityLog = NoActivityLog()) {
    self.init(unmount: { try NSWorkspace.shared.unmountAndEjectDevice(at: $0) }, log: log)
  }

  package init(unmount: @escaping Unmount, log: any ActivityLog = NoActivityLog()) {
    self.unmount = unmount
    self.log = log
  }

  public func eject(_ volume: KindleVolume) async throws(EjectError) {
    do {
      try unmount(volume.mountURL)
    } catch {
      let failure = Self.failure(error as NSError)
      let reason =
        switch failure {
        case .inUse: "something is still open on it"
        case .failed(let detail): detail
        }
      log.warning(.usb, "Couldn't eject \(volume.name): \(reason)")
      throw failure
    }
    log.info(.usb, "Ejected \(volume.name)")
  }

  /// A busy volume (`fBsyErr`) is the one failure the user can fix, by closing what's open on it.
  package static func failure(_ error: NSError) -> EjectError {
    error.domain == NSOSStatusErrorDomain && error.code == -47
      ? .inUse : .failed(error.localizedDescription)
  }
}
