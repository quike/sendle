import SendleDomain
import SwiftUI

/// The A–Z bar down the right edge of the books: click or drag a letter to jump there. The full
/// bar always shows every letter; the compact one shows the letters with books while the pointer
/// is near it (`isHovered`, which the books' scroll view sets), on a dark capsule so it reads over
/// the covers it floats on.
struct AlphabetRail<ID: Hashable & Sendable>: View {
  static var width: CGFloat { 16 }
  /// What the full bar takes from the books: itself plus the grid's column spacing.
  static var reservedWidth: CGFloat { width + 10 }
  static var compactLetterHeight: CGFloat { 14 }
  /// Room between the compact bar's letters and its capsule.
  static var capsuleInset: CGFloat { 4 }

  let jump: LetterJump<ID>
  let style: JumpBarStyle
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isFull = style == .full
    let isShown = isFull || jump.isHovered || jump.draggedLetter != nil
    GeometryReader { geometry in
      let letters = jump.letters(style)
      let height =
        isFull
        ? geometry.size.height
        : min(
          CGFloat(letters.count) * Self.compactLetterHeight,
          geometry.size.height - 2 * Self.capsuleInset)
      HStack(spacing: 6) {
        Spacer(minLength: 0)
        if let dragged = jump.draggedLetter {
          DraggedLetter(letter: dragged)
        }
        LetterColumn(jump: jump, letters: letters, height: height)
          .padding(isFull ? 0 : Self.capsuleInset)
          .background {
            if !isFull {
              Capsule()
                .fill(Theme.floating)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
            }
          }
          .opacity(isShown ? 1 : 0)
          .allowsHitTesting(isShown)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isShown)
    }
    .frame(width: 120)
  }
}

/// The A–Z bar on a card of its own beside the panel's, level with the books. The compact bar
/// shows while the pointer is near the books' edge on that side, the gap and the card included.
struct FloatingRail<ID: Hashable & Sendable>: View {
  let jump: LetterJump<ID>
  let style: JumpBarStyle
  let side: RailSide
  /// The panel's card and the books, in the window.
  let card: CGRect
  let books: CGRect
  /// No sheet or other screen covers the books, so the card comes in and goes as they do.
  let isUncovered: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isFull = style == .full
    let isAvailable = isUncovered && jump.isShown
    let isShown = isAvailable && (isFull || jump.isHovered || jump.draggedLetter != nil)
    let letters = jump.letters(style)
    let inset = AlphabetRail<ID>.capsuleInset
    let frame = FloatingControls.railFrame(
      card: card, books: books, side: side,
      height: isFull
        ? nil : CGFloat(letters.count) * AlphabetRail<ID>.compactLetterHeight + 2 * inset)
    let isTrailing = side == .trailing
    let outer: Alignment = isTrailing ? .trailing : .leading
    let zone =
      isTrailing
      ? CGRect(x: books.maxX, y: books.minY, width: frame.maxX - books.maxX, height: books.height)
      : CGRect(x: frame.minX, y: books.minY, width: books.minX - frame.minX, height: books.height)
    ZStack(alignment: outer) {
      if !isFull, isAvailable {
        Color.clear.contentShape(Rectangle())
      }
      if isShown {
        FloatingCard(size: frame.size, cornerRadius: frame.width / 2) {
          LetterColumn(jump: jump, letters: letters, height: frame.height - 2 * inset)
        }
        .transition(.offset(x: isTrailing ? -12 : 12).combined(with: .opacity))
      }
    }
    // Without the clear hover shape the stack is only as wide as the card, so this places it.
    .frame(width: zone.width, height: zone.height, alignment: outer)
    .overlay(alignment: isTrailing ? .leading : .trailing) {
      if let dragged = jump.draggedLetter {
        DraggedLetter(letter: dragged).offset(x: isTrailing ? -62 : 62)
      }
    }
    .onContinuousHover { phase in
      guard !isFull else { return }
      if case .active = phase { jump.isHovered = true } else { jump.isHovered = false }
    }
    .offset(x: zone.minX, y: zone.minY)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isShown)
  }
}

/// The big letter beside the bar while the pointer drags along it.
private struct DraggedLetter: View {
  let letter: String

  var body: some View {
    Text(letter)
      .font(.system(size: 28, weight: .bold))
      .frame(width: 56, height: 56)
      .background(Theme.floating, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12)))
      .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// The letters themselves: click or drag along them to jump.
private struct LetterColumn<ID: Hashable & Sendable>: View {
  let jump: LetterJump<ID>
  let letters: [String]
  let height: CGFloat

  var body: some View {
    let withBooks = Set(jump.index?.lettersWithBooks ?? [])
    let width = AlphabetRail<ID>.width
    VStack(spacing: 0) {
      ForEach(letters, id: \.self) { letter in
        let isCurrent = (jump.draggedLetter ?? jump.currentLetter) == letter
        Text(letter)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            isCurrent
              ? .white : withBooks.contains(letter) ? Theme.accent : Color.white.opacity(0.18)
          )
          .frame(width: width - 2, height: height / CGFloat(max(letters.count, 1)))
          .background(isCurrent ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
      }
    }
    .frame(width: width, height: height)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if let letter = RailLayout.letter(at: value.location.y, height: height, letters: letters)
          {
            jump.drag(to: letter)
          }
        }
        .onEnded { _ in jump.endDrag() }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Jump to letter")
    .accessibilityValue(jump.currentLetter ?? "")
    .accessibilityAdjustableAction { direction in
      let shown = jump.index?.lettersWithBooks ?? []
      let current = jump.currentLetter.flatMap { shown.firstIndex(of: $0) } ?? -1
      let next = direction == .increment ? current + 1 : current - 1
      if shown.indices.contains(next) { jump.jump(to: shown[next]) }
    }
  }
}

/// The books' scroll view, with the A–Z bar over its right edge while sorted by title or author,
/// or on a card of its own on `floatingSide`. The compact bar shows while the pointer is near
/// that edge, the bar included.
struct BooksScroll<ID: Hashable & Sendable, Content: View>: View {
  private static var top: String { "top" }

  let jump: LetterJump<ID>
  let style: JumpBarStyle
  /// Bumped when the list should start at the top again.
  let scrollToTopRequests: Int
  /// Room kept clear at the bottom, for the send bar.
  var bottomRoom: CGFloat = 0
  /// The side of the floating A–Z card, or nil while the bar sits inside the books.
  var floatingSide: RailSide?
  @ViewBuilder let content: Content

  var body: some View {
    let isAttached = floatingSide == nil
    let fullRail = isAttached && jump.isShown && style == .full
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) { content }
            .id(Self.top)
            .padding(.trailing, fullRail ? AlphabetRail<ID>.reservedWidth : 0)
            .padding(.bottom, 6 + bottomRoom)
        }
        .scrollOverflow(.horizontal)
        .contentMargins(.vertical, BooksArea.liftRoom, for: .scrollContent)
        .scrollIndicators(.never)
        .scrollPosition(id: Bindable(jump).top, anchor: .top)
        .onChange(of: scrollToTopRequests) { proxy.scrollTo(Self.top, anchor: .top) }
      }
      .overlay(alignment: .trailing) {
        if isAttached, jump.isShown {
          AlphabetRail(jump: jump, style: style).padding(.bottom, bottomRoom)
        }
      }
      .onContinuousHover { phase in
        guard case .active(let point) = phase else { return jump.isHovered = false }
        jump.isHovered =
          floatingSide == .leading ? point.x < 36 : point.x > geometry.size.width - 36
      }
    }
    .anchorPreference(key: BooksAreaKey.self, value: .bounds) { $0 }
    .padding(BooksArea.insets)
  }
}

extension View {
  /// Reaches a scroll view `amount` past its frame at `edges` and insets its content by as much,
  /// so a selected cover's frame, a lifted cover and their shadows are never cut there while the
  /// books rest where they would without it.
  func scrollOverflow(_ edges: Edge.Set = .all, _ amount: CGFloat = BooksArea.liftRoom)
    -> some View
  {
    contentMargins(edges, amount, for: .scrollContent).padding(edges, -amount)
  }
}

/// Where the books show on the library screen. As they scroll they are cut as far below the
/// controls and above the card's bottom edge as the grid's covers sit from the card's sides, and
/// they rest `liftRoom` inside that, so a selected or lifted cover is never cut.
package enum BooksArea {
  /// The library screen's padding inside the card.
  package static let screenPadding: CGFloat = 14
  /// Between the controls and what the screen shows under them.
  package static let controlsGap: CGFloat = 10
  /// The grid's own padding at its sides.
  package static let gridInset: CGFloat = 4
  /// Room for a selected cover's frame, a lifted cover and their shadows.
  package static let liftRoom: CGFloat = 10

  /// What the books take off the space the screen gives them, to be cut at the covers' side margin.
  package static var insets: EdgeInsets {
    let margin = screenPadding + gridInset
    return EdgeInsets(
      top: margin - controlsGap, leading: 0, bottom: margin - screenPadding, trailing: 0)
  }
}
