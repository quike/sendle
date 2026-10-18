import SwiftUI

/// The A–Z bar down the right edge of the books: click or drag a letter to jump there. The full
/// bar always shows every letter; the compact one shows the letters with books while the pointer
/// is near it (`isRailHovered`, which the library's scroll view sets).
struct AlphabetRail: View {
  static let width: CGFloat = 16
  private static let compactLetterHeight: CGFloat = 14

  let library: LibraryViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isFull = library.jumpBar == .full
    let isShown = isFull || library.isRailHovered || library.draggedLetter != nil
    GeometryReader { geometry in
      let letters = library.railLetters
      let height =
        isFull
        ? geometry.size.height
        : min(CGFloat(letters.count) * Self.compactLetterHeight, geometry.size.height)
      HStack(spacing: 6) {
        Spacer(minLength: 0)
        if let dragged = library.draggedLetter {
          Text(dragged)
            .font(.system(size: 28, weight: .bold))
            .frame(width: 56, height: 56)
            .background(
              Color(hex: 0x161b29).opacity(0.96), in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        letterColumn(letters, height: height, isFull: isFull)
          .opacity(isShown ? 1 : 0)
          .allowsHitTesting(isShown)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isShown)
    }
    .frame(width: 120)
  }

  private func letterColumn(_ letters: [String], height: CGFloat, isFull: Bool) -> some View {
    let withBooks = Set(library.index?.lettersWithBooks ?? [])
    return VStack(spacing: 0) {
      ForEach(letters, id: \.self) { letter in
        let isCurrent = (library.draggedLetter ?? library.currentLetter) == letter
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
    .background(
      isFull ? .clear : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)
    )
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if let letter = RailLayout.letter(at: value.location.y, height: height, letters: letters)
          {
            library.drag(to: letter)
          }
        }
        .onEnded { _ in library.endDrag() }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Jump to letter")
    .accessibilityValue(library.currentLetter ?? "")
    .accessibilityAdjustableAction { direction in
      let shown = library.index?.lettersWithBooks ?? []
      let current = library.currentLetter.flatMap { shown.firstIndex(of: $0) } ?? -1
      let next = direction == .increment ? current + 1 : current - 1
      if shown.indices.contains(next) { library.jump(to: shown[next]) }
    }
  }
}
