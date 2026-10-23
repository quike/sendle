import SwiftUI

/// Which of a segmented switch's options is on, where its highlight sits on a track of equal
/// segments, and where a step from it lands.
package struct SegmentedChoice<Value: Hashable> {
  package let options: [Value]
  package let selection: Value

  package init(options: [Value], selection: Value) {
    self.options = options
    self.selection = selection
  }

  package var index: Int { options.firstIndex(of: selection) ?? 0 }

  package func segmentWidth(in width: CGFloat) -> CGFloat {
    width / CGFloat(max(options.count, 1))
  }

  /// The highlight's leading edge on a track `width` wide.
  package func highlightOffset(in width: CGFloat) -> CGFloat {
    segmentWidth(in: width) * CGFloat(index)
  }

  /// The next option, or the previous one; the ends stay put.
  package func stepped(forward: Bool) -> Value {
    let next = index + (forward ? 1 : -1)
    return options.indices.contains(next) ? options[next] : selection
  }
}

/// Sendle's segmented control: the options on a glass capsule, with a highlight that slides to
/// the chosen one. VoiceOver reads its name and choice and adjusts it; the arrow keys step along
/// it.
struct SegmentedSwitch<Value: Hashable>: View {
  let label: String
  let options: [Value]
  let selection: Value
  /// Shares out the width it is offered; otherwise every segment fits the longest title.
  var fillsWidth = false
  let title: (Value) -> String
  let choose: (Value) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let choice = SegmentedChoice(options: options, selection: selection)
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        let isOn = option == selection
        Button {
          if !isOn { choose(option) }
        } label: {
          segment(title(option), isOn: isOn)
        }
        .buttonStyle(.plain)
      }
    }
    .background(alignment: .leading) {
      GeometryReader { geometry in
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.14))
          .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
          .frame(width: choice.segmentWidth(in: geometry.size.width))
          .offset(x: choice.highlightOffset(in: geometry.size.width))
      }
    }
    .animation(reduceMotion ? nil : Theme.press, value: choice.index)
    .padding(2)
    .background(Theme.glass, in: Capsule(style: .continuous))
    .overlay(Capsule(style: .continuous).strokeBorder(Theme.line))
    .fixedSize(horizontal: !fillsWidth, vertical: true)
    .onMoveCommand { direction in
      guard direction == .left || direction == .right else { return }
      let next = choice.stepped(forward: direction == .right)
      if next != selection { choose(next) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(title(selection))
    .accessibilityAdjustableAction { direction in
      let next = choice.stepped(forward: direction == .increment)
      if next != selection { choose(next) }
    }
  }

  /// Every title sits hidden under each segment's own, so the segments are as wide as the longest.
  private func segment(_ text: String, isOn: Bool) -> some View {
    ZStack {
      ForEach(options, id: \.self) { option in
        Text(title(option)).hidden()
      }
      Text(text).foregroundStyle(isOn ? Theme.text : Theme.muted)
    }
    .font(.system(size: 11, weight: .semibold))
    .lineLimit(1)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 22)
    .contentShape(Capsule(style: .continuous))
  }
}
