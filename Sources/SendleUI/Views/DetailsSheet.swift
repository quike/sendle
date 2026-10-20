import SendleDomain
import SwiftUI

/// Dims the library above the edit sheet; a click on it cancels the sheet.
struct DetailsDim: View {
  let panel: PanelModel

  var body: some View {
    Color.black.opacity(0.45)
      .contentShape(Rectangle())
      .onTapGesture { panel.closeDetails() }
      .accessibilityHidden(true)
  }
}

/// A book's details, in a sheet that rises over the bottom of the library (spec §3.2). Its
/// fields scroll on a card too short for them all.
struct DetailsSheet: View {
  /// How much of the card's height the sheet covers.
  static let share: CGFloat = 0.7

  let panel: PanelModel
  let details: BookDetailsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Capsule()
        .fill(Theme.glassHigh)
        .frame(width: 36, height: 4)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          DetailsCoverRow(panel: panel, details: details)
          DetailsFields(details: details)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
      }
      .scrollIndicators(.never)
      .scrollBounceBehavior(.basedOnSize)
      DetailsActions(panel: panel, details: details)
        .padding([.horizontal, .bottom], 14)
    }
    .overlay(alignment: .topTrailing) {
      CoverMark(symbol: "pencil", color: Theme.warm)
        .padding(.top, 10)
        .padding(.trailing, 14)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity)
    .frame(height: (panel.cardSize.height * Self.share).rounded())
    .background(CardBackground())
    .shadow(color: .black.opacity(0.5), radius: 17, y: -8)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Edit details")
    .frame(maxHeight: .infinity, alignment: .bottom)
  }
}

/// The error of a failed save above Revert all, Cancel and Save.
private struct DetailsActions: View {
  let panel: PanelModel
  let details: BookDetailsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let error = details.errorText {
        FieldNote(text: error, color: Theme.danger)
      }
      HStack(spacing: 8) {
        Button {
          details.revertAll()
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(CircleButtonStyle())
        .help("Revert all to Books")
        .accessibilityLabel("Revert all to Books")
        Spacer(minLength: 0)
        Button {
          panel.closeDetails()
        } label: {
          KeyHintLabel(title: "Cancel", key: "esc")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel("Cancel")
        Button {
          Task { await panel.saveDetails() }
        } label: {
          KeyHintLabel(title: "Save", key: "↩")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!panel.canSaveDetails)
        .accessibilityLabel("Save")
      }
    }
    .padding(.top, 8)
  }
}

/// A button's title with the key that does the same, as "Save ↩".
private struct KeyHintLabel: View {
  let title: String
  let key: String

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
      Text(key).font(.system(size: 10, weight: .semibold)).opacity(0.7)
    }
  }
}
