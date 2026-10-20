import SwiftUI

/// The whole card under the menu bar icon: its arrow, the current screen and the settings sheet.
public struct PanelView: View {
  /// Room around the card for its arrow and shadow; the window is this much larger than the card.
  nonisolated public static let margins = EdgeInsets(top: 12, leading: 24, bottom: 46, trailing: 24)
  nonisolated public static let windowSize = windowSize(margins: margins)

  nonisolated public static func windowSize(margins: EdgeInsets) -> CGSize {
    windowSize(margins: margins, card: Theme.cardSize)
  }

  nonisolated package static func windowSize(margins: EdgeInsets, card: CGSize) -> CGSize {
    CGSize(
      width: card.width + margins.leading + margins.trailing,
      height: card.height + margins.top + margins.bottom)
  }

  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(panel: PanelModel) {
    self.panel = panel
  }

  public var body: some View {
    let margins = panel.windowMargins
    let card = CGRect(origin: CGPoint(x: margins.leading, y: margins.top), size: panel.cardSize)
    PanelChrome(arrowOffset: arrowOffset, margins: margins, size: panel.cardSize) {
      let isShowingLogs = panel.route == .logs
      let sheet = ScreenMotion.sheet(reduceMotion: reduceMotion).transition
      let motion = ScreenMotion.animation(reduceMotion: reduceMotion)
      ZStack {
        Group {
          switch panel.screenUnderLogs {
          case .library, .logs: LibraryScreen(panel: panel)
          case .setup: SetupScreen(panel: panel)
          case .queue: QueueScreen(panel: panel)
          }
        }
        .disabled(
          panel.isShowingSettings || panel.duplicateReview != nil || panel.bookDetails != nil
            || isShowingLogs)
        if panel.isShowingSettings {
          SettingsSheet(panel: panel).transition(sheet)
        }
        if isShowingLogs {
          LogsScreen(panel: panel).transition(sheet)
        }
        if let review = panel.duplicateReview {
          DuplicateSheet(panel: panel, review: review).transition(sheet)
        }
        if let details = panel.bookDetails {
          DetailsDim(panel: panel).transition(.opacity)
          DetailsSheet(panel: panel, details: details).transition(sheet)
        }
      }
      .animation(motion, value: panel.isShowingSettings)
      .animation(motion, value: isShowingLogs)
      .animation(motion, value: panel.duplicateReview != nil)
      .animation(motion, value: panel.bookDetails != nil)
    }
    .overlayPreferenceValue(BooksAreaKey.self) { books in
      GeometryReader { proxy in
        if let books, let side = panel.floatingRailSide {
          floatingRail(card: card, books: proxy[books], side: side)
        }
      }
    }
    .overlay(alignment: .topLeading) {
      let frame = FloatingControls.sendFrame(card: card)
      ZStack {
        if panel.showsSendCard {
          FloatingCard(size: frame.size, cornerRadius: FloatingControls.sendRadius) {
            SendBarContent(panel: panel)
          }
          .transition(.offset(y: -14).combined(with: .opacity))
        }
      }
      .offset(x: frame.minX, y: frame.minY)
      .animation(reduceMotion ? nil : Theme.press, value: panel.showsSendCard)
    }
    .environment(panel.pointer)
    .coordinateSpace(PointerModel.space)
    .onContinuousHover(coordinateSpace: PointerModel.space) { phase in
      switch phase {
      case .active(let location): panel.pointer.location = location
      case .ended: panel.pointer.location = nil
      }
    }
  }

  @ViewBuilder
  private func floatingRail(card: CGRect, books: CGRect, side: RailSide) -> some View {
    let style = panel.library.jumpBar
    let isUncovered = panel.showsFloatingRail
    if panel.side == .kindle {
      FloatingRail(
        jump: panel.kindle.letterJump, style: style, side: side, card: card, books: books,
        isUncovered: isUncovered)
    } else {
      FloatingRail(
        jump: panel.library.letterJump, style: style, side: side, card: card, books: books,
        isUncovered: isUncovered)
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
  let margins: EdgeInsets
  let size: CGSize
  let content: Content

  package init(
    arrowOffset: CGFloat, margins: EdgeInsets = PanelView.margins, size: CGSize = Theme.cardSize,
    @ViewBuilder content: () -> Content
  ) {
    self.arrowOffset = arrowOffset
    self.margins = margins
    self.size = size
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
        .frame(width: size.width, height: size.height)
        .background(CardBackground())
        .clipShape(shape)
        .background(CardShadow(shape: shape))
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .padding(margins)
    .foregroundStyle(Theme.text)
    .environment(\.colorScheme, .dark)
  }
}

/// A card of the panel's kind, as big as `size`: its background and its two-layer shadow. The
/// floating send card and A–Z card are drawn with it.
package struct FloatingCard<Content: View>: View {
  let size: CGSize
  let cornerRadius: CGFloat
  let content: Content

  package init(size: CGSize, cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
    self.size = size
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  package var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    content
      .frame(width: size.width, height: size.height)
      .background(CardBackground(cornerRadius: cornerRadius))
      .clipShape(shape)
      .background(CardShadow(shape: shape))
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

/// Where the books are, so the floating A–Z card can stand level with them outside the card.
struct BooksAreaKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }

  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
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
