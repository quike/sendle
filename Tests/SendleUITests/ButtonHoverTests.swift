import CoreGraphics
import SendleUI
import SwiftUI
import Testing

@MainActor
struct ButtonHoverTests {
  @Test
  func theSurfaceBrightensUnderThePointer() {
    #expect(ButtonHover.surface(isHovered: false, isPressed: false) == Theme.glass)
    #expect(ButtonHover.surface(isHovered: true, isPressed: false) == Theme.glassHigh)
  }

  @Test
  func aHeldButtonKeepsTheBrightSurfaceWithOrWithoutThePointer() {
    #expect(ButtonHover.surface(isHovered: false, isPressed: true) == Theme.glassHigh)
    #expect(ButtonHover.surface(isHovered: true, isPressed: true) == Theme.glassHigh)
  }

  @Test
  func theIconAndTheTextBrightenUnderThePointer() {
    #expect(ButtonHover.brightness(isHovered: false) == 0)
    #expect(ButtonHover.brightness(isHovered: true) > 0)
  }

  @Test
  func theEaseIsShort() {
    #expect(ButtonHover.animation == .easeOut(duration: 0.15))
  }
}

struct ButtonHoverHitTests {
  let frame = CGRect(x: 10, y: 20, width: 30, height: 30)

  @Test
  func withoutAPointerNothingIsHovered() {
    #expect(!ButtonHover.isOver(nil, frame))
  }

  @Test
  func thePointerIsOverTheFramesItIsInside() {
    #expect(ButtonHover.isOver(CGPoint(x: 25, y: 35), frame))
  }

  @Test
  func thePointerIsNotOverTheFramesItIsOutside() {
    #expect(!ButtonHover.isOver(CGPoint(x: 41, y: 35), frame))
  }
}

@MainActor
struct PointerModelTests {
  @Test
  func closingThePanelForgetsThePointer() {
    let (panel, _) = PanelHarness().makePanel()
    panel.pointer.location = CGPoint(x: 25, y: 35)

    panel.panelDidClose()

    #expect(panel.pointer.location == nil)
  }
}
