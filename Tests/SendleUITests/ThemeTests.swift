import SendleUI
import SwiftUI
import Testing

struct ThemeTests {
  @Test(
    arguments: [
      (Theme.background, 0x0a0e1a), (Theme.text, 0xf3f5fa), (Theme.accent, 0x3d8bff),
      (Theme.warm, 0xffb46b), (Theme.live, 0x4ade80), (Theme.danger, 0xff5c5c),
      (Theme.brandStart, 0x7c5cff),
    ] as [(Color, Int)])
  func solidColoursMatchTheSpec(color: Color, hex: Int) {
    let resolved = color.resolve(in: EnvironmentValues())

    #expect(Int((resolved.red * 255).rounded()) == hex >> 16 & 0xff)
    #expect(Int((resolved.green * 255).rounded()) == hex >> 8 & 0xff)
    #expect(Int((resolved.blue * 255).rounded()) == hex & 0xff)
  }

  @Test(
    arguments: [
      (Theme.muted, 0.58), (Theme.faint, 0.34), (Theme.glass, 0.055), (Theme.glassHigh, 0.10),
      (Theme.line, 0.085),
    ] as [(Color, Double)])
  func translucentWhitesMatchTheSpec(color: Color, opacity: Double) {
    let resolved = color.resolve(in: EnvironmentValues())

    #expect(resolved.red == 1)
    #expect(abs(Double(resolved.opacity) - opacity) < 0.001)
  }

  @Test func eachKindOfDestinationKeepsItsColour() {
    #expect(Theme.tint(for: .email) == Theme.accent)
    #expect(Theme.tint(for: .usb) == Theme.live)
  }
}
