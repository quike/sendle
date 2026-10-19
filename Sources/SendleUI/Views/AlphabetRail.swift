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
  private static var compactLetterHeight: CGFloat { 14 }
  /// Room between the compact bar's letters and its capsule.
  private static var capsuleInset: CGFloat { 4 }

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
          Text(dragged)
            .font(.system(size: 28, weight: .bold))
            .frame(width: 56, height: 56)
            .background(Theme.floating, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        letterColumn(letters, height: height)
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

  private func letterColumn(_ letters: [String], height: CGFloat) -> some View {
    let withBooks = Set(jump.index?.lettersWithBooks ?? [])
    return VStack(spacing: 0) {
      ForEach(letters, id: \.self) { letter in
        let isCurrent = (jump.draggedLetter ?? jump.currentLetter) == letter
        Text(letter)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            isCurrent
              ? .white : withBooks.contains(letter) ? Theme.accent : Color.white.opacity(0.18)
          )
          .frame(width: Self.width - 2, height: height / CGFloat(max(letters.count, 1)))
          .background(isCurrent ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
      }
    }
    .frame(width: Self.width, height: height)
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

/// The books' scroll view, with the A–Z bar over its right edge while sorted by title or author.
/// The compact bar shows while the pointer is near the right edge, the bar included.
struct BooksScroll<ID: Hashable & Sendable, Content: View>: View {
  private static var top: String { "top" }

  let jump: LetterJump<ID>
  let style: JumpBarStyle
  /// Bumped when the list should start at the top again.
  let scrollToTopRequests: Int
  /// Room kept clear at the bottom, for the send bar.
  var bottomRoom: CGFloat = 0
  @ViewBuilder let content: Content

  var body: some View {
    let fullRail = jump.isShown && style == .full
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) { content }
            .id(Self.top)
            .padding(.trailing, fullRail ? AlphabetRail<ID>.reservedWidth : 0)
            .padding(.bottom, 6 + bottomRoom)
        }
        .scrollOverflow()
        .scrollIndicators(.never)
        .scrollPosition(id: Bindable(jump).top, anchor: .top)
        .onChange(of: scrollToTopRequests) { proxy.scrollTo(Self.top, anchor: .top) }
      }
      .overlay(alignment: .trailing) {
        if jump.isShown {
          AlphabetRail(jump: jump, style: style).padding(.bottom, bottomRoom)
        }
      }
      .onContinuousHover { phase in
        guard case .active(let point) = phase else { return jump.isHovered = false }
        jump.isHovered = point.x > geometry.size.width - 36
      }
    }
  }
}

extension View {
  /// Reaches a scroll view `amount` past its frame at `edges` and insets its content by as much,
  /// so a selected cover's frame, a lifted cover and their shadows are never cut there while the
  /// books rest where they would without it.
  func scrollOverflow(_ edges: Edge.Set = .all, _ amount: CGFloat = 10) -> some View {
    contentMargins(edges, amount, for: .scrollContent).padding(edges, -amount)
  }
}
