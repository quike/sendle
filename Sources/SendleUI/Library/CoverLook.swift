import SendleDomain

/// How a cover is dimmed for what the book can do: iCloud-only books stay readable, locked ones fade.
package struct CoverLook: Equatable {
  package let saturation: Double
  package let brightness: Double
  package let showsCloud: Bool

  package init(saturation: Double, brightness: Double, showsCloud: Bool) {
    self.saturation = saturation
    self.brightness = brightness
    self.showsCloud = showsCloud
  }

  package static func of(_ availability: Availability) -> CoverLook {
    switch availability {
    case .ready: CoverLook(saturation: 1, brightness: 0, showsCloud: false)
    case .inCloudOnly: CoverLook(saturation: 0.6, brightness: -0.1, showsCloud: true)
    case .protected, .missing: CoverLook(saturation: 0.2, brightness: -0.3, showsCloud: false)
    }
  }
}
