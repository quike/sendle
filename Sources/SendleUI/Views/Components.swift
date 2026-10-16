import SwiftUI

/// The dark card: background, a soft glow at the top and a 1 px inner hairline.
struct CardBackground: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    ZStack(alignment: .top) {
      Theme.background
      RadialGradient(
        colors: [Theme.accent.opacity(0.22), .clear], center: .top, startRadius: 0,
        endRadius: 230
      )
      .frame(height: 230)
      .offset(y: -100)
    }
    .clipShape(shape)
    .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
  }
}

extension View {
  /// A translucent glass surface with a hairline, as house-control draws its controls.
  func glass(cornerRadius: CGFloat, highlighted: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return background(highlighted ? Theme.glassHigh : Theme.glass, in: shape)
      .overlay(shape.strokeBorder(Theme.line))
  }
}

struct BrandBadge: View {
  var body: some View {
    Image(systemName: "book.closed.fill")
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 30, height: 30)
      .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityHidden(true)
  }
}

struct PanelHeader<Trailing: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(spacing: 10) {
      BrandBadge()
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 15, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
      }
      Spacer(minLength: 8)
      trailing
    }
  }
}

struct SectionLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 9.5, weight: .semibold))
      .kerning(0.9)
      .foregroundStyle(Theme.faint)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 2)
      .accessibilityAddTraits(.isHeader)
  }
}

struct StatusDot: View {
  let color: Color

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      .shadow(color: color, radius: 4)
      .accessibilityHidden(true)
  }
}

struct FormatBadge: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 8.5, weight: .bold))
      .kerning(0.3)
      .foregroundStyle(Color.white.opacity(0.7))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
  }
}

/// The press feedback the button styles share; with Reduce Motion on, buttons don't move.
private struct PressEffect: ViewModifier {
  let isPressed: Bool
  let scale: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .scaleEffect(isPressed && !reduceMotion ? scale : 1)
      .animation(reduceMotion ? nil : Theme.press, value: isPressed)
  }
}

extension View {
  fileprivate func pressEffect(_ isPressed: Bool, scale: CGFloat = 0.97) -> some View {
    modifier(PressEffect(isPressed: isPressed, scale: scale))
  }
}

/// The blue call to action. No glow: inside a scroll view its shadow draws a grey band.
struct PrimaryButtonStyle: ButtonStyle {
  var fullWidth = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12.5, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 34)
      .background(Theme.action, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .opacity(isEnabled ? 1 : 0.4)
      .pressEffect(configuration.isPressed)
      .contentShape(Rectangle())
  }
}

struct SecondaryButtonStyle: ButtonStyle {
  var fullWidth = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 12)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
      .glass(cornerRadius: 11, highlighted: configuration.isPressed)
      .opacity(isEnabled ? 1 : 0.4)
      .pressEffect(configuration.isPressed)
      .contentShape(Rectangle())
  }
}

/// Text-only actions such as "Set up later".
struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(configuration.isPressed ? Theme.text : Theme.muted)
      .contentShape(Rectangle())
  }
}

/// The 30 pt round buttons in headers.
struct CircleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(Color(hex: 0xc9d3ea))
      .frame(width: 30, height: 30)
      .background(configuration.isPressed ? Theme.glassHigh : Theme.glass, in: Circle())
      .overlay(Circle().strokeBorder(Theme.line))
      .pressEffect(configuration.isPressed, scale: 0.94)
  }
}

/// A one-line explanation under a field, in the colour of how much it matters.
struct FieldNote: View {
  let text: String
  var color = Theme.muted

  var body: some View {
    Text(text)
      .font(.system(size: 10.5))
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// What failed and its one-click fix, in the error toast's colours.
struct NoticeView: View {
  let problem: Problem
  let onFix: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(problem.title).font(.system(size: 12, weight: .semibold))
        if let message = problem.message {
          Text(message).font(.system(size: 11)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 4)
      if let fix = problem.fix {
        Button("\(fix.label) →", action: onFix)
          .buttonStyle(.plain)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color(hex: 0x9cc2ff))
      }
      Button(action: onDismiss) {
        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
      }
      .buttonStyle(.plain)
      .foregroundStyle(Theme.faint)
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Theme.danger.opacity(0.12), in: shape)
    .overlay(shape.strokeBorder(Theme.danger.opacity(0.35)))
  }
}
