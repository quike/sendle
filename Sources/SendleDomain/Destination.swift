import Foundation

/// The Send to Kindle address of a device, e.g. `reader@kindle.com`.
public struct KindleEmail: RawRepresentable, Hashable, Sendable, Codable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var isAmazonAddress: Bool {
    let address = rawValue.lowercased()
    return address.hasSuffix("@kindle.com") || address.hasSuffix("@kindle.cn")
  }
}

/// A Kindle mounted as a drive.
public struct KindleVolume: Hashable, Sendable {
  public let id: String
  public let name: String
  public let mountURL: URL

  public init(id: String, name: String, mountURL: URL) {
    self.id = id
    self.name = name
    self.mountURL = mountURL
  }
}

public enum DestinationKind: String, Sendable, Codable, CaseIterable {
  case email
  case usb
}

public enum Destination: Hashable, Sendable {
  case email(KindleEmail)
  case usb(KindleVolume)

  public var kind: DestinationKind {
    switch self {
    case .email: .email
    case .usb: .usb
    }
  }
}

public enum EmailAddress {
  /// A deliberately loose check: something before a single "@" and a dotted domain after it.
  public static func isPlausible(_ text: String) -> Bool {
    let parts = text.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !text.contains(where: \.isWhitespace) else {
      return false
    }
    let domain = parts[1]
    return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
  }
}
