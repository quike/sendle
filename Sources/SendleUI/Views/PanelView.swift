import SwiftUI

/// The whole card under the menu bar icon: its arrow, the current screen and the settings sheet.
public struct PanelView: View {
  /// Room around the card for its arrow and shadow; the window is this much larger than the card.
  public static let margins = EdgeInsets(top: 12, leading: 24, bottom: 46, trailing: 24)
  public static let windowSize = CGSize(
    width: Theme.cardSize.width + margins.leading + margins.trailing,
    height: Theme.cardSize.height + margins.top + margins.bottom)

  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(panel: PanelModel) {
    self.panel = panel
  }

  public var body: some View {
    PanelChrome(arrowOffset: arrowOffset) {
      ZStack {
        Group {
          switch panel.route {
          case .library: LibraryScreen(panel: panel)
          case .setup: SetupScreen(panel: panel)
          case .queue: QueueScreen(panel: panel)
          case .logs: LogsScreen(panel: panel)
          }
        }
        .disabled(panel.isShowingSettings || panel.duplicateReview != nil)
        if panel.isShowingSettings {
          SettingsSheet(panel: panel).transition(.move(edge: .bottom))
        }
        if let review = panel.duplicateReview {
          DuplicateSheet(panel: panel, review: review).transition(.move(edge: .bottom))
        }
      }
      .animation(reduceMotion ? nil : Theme.press, value: panel.isShowingSettings)
      .animation(reduceMotion ? nil : Theme.press, value: panel.duplicateReview != nil)
    }
  }

  /// The arrow follows the status item, but never past the card's rounded corners.
  private var arrowOffset: CGFloat {
    let inset = Theme.cardRadius + 10
    let x = min(max(panel.arrowX, inset), Theme.cardSize.width - inset)
    return x - Theme.cardSize.width / 2
  }
}

/// The card without what it shows: its arrow, background and shadow, in a window-sized frame.
package struct PanelChrome<Content: View>: View {
  let arrowOffset: CGFloat
  let content: Content

  package init(arrowOffset: CGFloat, @ViewBuilder content: () -> Content) {
    self.arrowOffset = arrowOffset
    self.content = content()
  }

  package var body: some View {
    let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    ZStack(alignment: .top) {
      PanelArrow()
        .fill(Theme.background)
        .frame(width: 20, height: 10)
        .offset(x: arrowOffset, y: -9)
      content
        .frame(width: Theme.cardSize.width, height: Theme.cardSize.height)
        .background(CardBackground())
        .clipShape(shape)
        .background(CardShadow(shape: shape))
    }
    .frame(width: Theme.cardSize.width, height: Theme.cardSize.height, alignment: .top)
    .padding(PanelView.margins)
    .foregroundStyle(Theme.text)
    .environment(\.colorScheme, .dark)
  }
}

/// house-control's card shadow (`0 18px 30px -12px`, `0 4px 12px -4px`): each layer is the card's
/// shape shrunk by its spread, so it follows the rounded corners and fades out inside the margins.
private struct CardShadow: View {
  let shape: RoundedRectangle

  var body: some View {
    ZStack {
      shape.fill(.black.opacity(0.55)).padding(12).offset(y: 18).blur(radius: 15)
      shape.fill(.black.opacity(0.4)).padding(4).offset(y: 4).blur(radius: 6)
    }
    .allowsHitTesting(false)
  }
}

private struct PanelArrow: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.closeSubpath()
    }
  }
}
