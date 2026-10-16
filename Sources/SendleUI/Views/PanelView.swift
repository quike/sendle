import SwiftUI

/// The whole card under the menu bar icon: its arrow, the current screen and the settings sheet.
public struct PanelView: View {
  /// Room around the card for its arrow and shadow; the window is this much larger than the card.
  public static let margins = EdgeInsets(top: 12, leading: 24, bottom: 34, trailing: 24)
  public static let windowSize = CGSize(
    width: Theme.cardSize.width + margins.leading + margins.trailing,
    height: Theme.cardSize.height + margins.top + margins.bottom)

  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(panel: PanelModel) {
    self.panel = panel
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    ZStack(alignment: .top) {
      PanelArrow()
        .fill(Theme.background)
        .frame(width: 20, height: 10)
        .offset(x: arrowOffset, y: -9)
      ZStack {
        Group {
          switch panel.route {
          case .library: LibraryScreen(panel: panel)
          case .setup: SetupScreen(panel: panel)
          }
        }
        .disabled(panel.isShowingSettings)
        if panel.isShowingSettings {
          SettingsSheet(panel: panel).transition(.move(edge: .bottom))
        }
      }
      .frame(width: Theme.cardSize.width, height: Theme.cardSize.height)
      .background(CardBackground())
      .clipShape(shape)
      .shadow(color: .black.opacity(0.55), radius: 22, y: 14)
      .animation(reduceMotion ? nil : Theme.press, value: panel.isShowingSettings)
    }
    .frame(width: Theme.cardSize.width, height: Theme.cardSize.height, alignment: .top)
    .padding(Self.margins)
    .foregroundStyle(Theme.text)
    .environment(\.colorScheme, .dark)
  }

  /// The arrow follows the status item, but never past the card's rounded corners.
  private var arrowOffset: CGFloat {
    let inset = Theme.cardRadius + 10
    let x = min(max(panel.arrowX, inset), Theme.cardSize.width - inset)
    return x - Theme.cardSize.width / 2
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
