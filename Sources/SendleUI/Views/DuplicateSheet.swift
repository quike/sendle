import SendleDomain
import SwiftUI

/// A book about to be copied that the Kindle already has, set beside its copy there.
struct DuplicateSheet: View {
  let panel: PanelModel
  @Bindable var review: DuplicateReviewModel

  var body: some View {
    let current = review.current
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Already on Kindle").font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(review.counter).font(.system(size: 11)).foregroundStyle(Theme.muted)
      }
      ConfidenceBadge(confidence: current.match.confidence, text: review.badge)
      Comparison(panel: panel, current: current, rows: review.rows)
      Spacer(minLength: 0)
      Toggle("Apply to the other duplicates", isOn: $review.appliesToRest)
        .toggleStyle(.checkbox)
        .font(.system(size: 11.5))
        .disabled(!review.canApplyToRest)
      FieldNote(text: review.note)
      HStack(spacing: 8) {
        ForEach(review.choices, id: \.self) { choice in
          if choice == review.defaultChoice {
            Button(choice.title) { panel.choose(choice) }
              .buttonStyle(PrimaryButtonStyle(fullWidth: true))
              .keyboardShortcut(.defaultAction)
          } else {
            Button(choice.title) { panel.choose(choice) }
              .buttonStyle(SecondaryButtonStyle(fullWidth: true))
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CardBackground())
  }
}

private struct ConfidenceBadge: View {
  let confidence: MatchConfidence
  let text: String

  var body: some View {
    let color = confidence == .sure ? Theme.live : Theme.warm
    Text(text)
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 9)
      .padding(.vertical, 3)
      .background(color.opacity(0.14), in: Capsule())
      .overlay(Capsule().strokeBorder(color.opacity(0.35)))
      .accessibilityLabel(text)
  }
}

/// The two copies in two columns, each fact on a line of its own so the columns read across.
private struct Comparison: View {
  let panel: PanelModel
  let current: DuplicateCase
  let rows: [ComparisonRow]

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
      GridRow {
        ColumnHead("To send · Library") {
          BookCover(panel: panel, book: current.book, size: .large)
        }
        ColumnHead("On Kindle") {
          KindleCover(
            kindle: panel.kindle,
            item: KindleItemViewModel(book: current.match.book, inLibrary: nil), size: .large)
        }
      }
      .padding(.bottom, 3)
      ForEach(rows, id: \.label) { row in
        GridRow {
          Fact(label: row.label, value: row.library, differs: row.differs)
          Fact(label: row.label, value: row.kindle, differs: row.differs)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }
}

private struct ColumnHead<Cover: View>: View {
  let title: String
  let cover: Cover

  init(_ title: String, @ViewBuilder cover: () -> Cover) {
    self.title = title
    self.cover = cover()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      SectionLabel(title)
      cover.frame(width: 72, height: 108)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct Fact: View {
  let label: String
  let value: String
  let differs: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label.uppercased())
        .font(.system(size: 8.5, weight: .semibold))
        .kerning(0.7)
        .foregroundStyle(Theme.faint)
      Text(value)
        .font(.system(size: 11.5, weight: differs ? .semibold : .regular))
        .foregroundStyle(differs ? Theme.warm : Theme.text)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(differs ? "\(value), differs" : value)
  }
}
