import SendleDomain
import SwiftUI

/// Dims the library above a details sheet; a click on it closes the sheet.
struct DetailsDim: View {
  let close: () -> Void

  var body: some View {
    Color.black.opacity(0.45)
      .contentShape(Rectangle())
      .onTapGesture(perform: close)
      .accessibilityHidden(true)
  }
}

/// A book's details, in a sheet that rises over the bottom of the library. A lookup's banner
/// tops it, and its edition list takes the fields' place while the user picks one.
struct DetailsSheet: View {
  /// How much of the card's height the sheet covers.
  static let share: CGFloat = 0.7

  let panel: PanelModel
  let details: BookDetailsViewModel

  var body: some View {
    DetailsSheetFrame(panel: panel, label: "Edit details") {
      if let banner = details.banner {
        LookupBannerView(panel: panel, details: details, banner: banner)
          // Clear of the edited mark in the corner.
          .padding(.top, 4)
          .padding(.bottom, 10)
      }
      if details.isPickingEdition {
        EditionList(panel: panel, details: details)
      } else {
        if let cover = details.foundCover {
          FoundCoverRow(panel: panel, details: details, cover: cover)
            .padding(.bottom, 10)
        }
        DetailsFactsRow(facts: details.facts) {
          DetailsCover(panel: panel, details: details)
        }
        DetailsFields(details: details)
      }
    } actions: {
      if details.isPickingEdition {
        EditionListActions(details: details)
      } else {
        DetailsActions(panel: panel, details: details)
      }
    } badge: {
      EditedMark()
    }
  }
}

/// A details sheet's grab handle, content, actions and top-right badge, on a card `share` of the
/// panel's height. The content scrolls on a card too short for it all.
struct DetailsSheetFrame<Content: View, Actions: View, Badge: View>: View {
  let panel: PanelModel
  let label: String
  @ViewBuilder let content: Content
  @ViewBuilder let actions: Actions
  @ViewBuilder let badge: Badge

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
          content
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
      }
      .scrollIndicators(.never)
      .scrollBounceBehavior(.basedOnSize)
      actions
        .padding([.horizontal, .bottom], 14)
    }
    .overlay(alignment: .topTrailing) {
      badge
        .padding(.top, 10)
        .padding(.trailing, 14)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity)
    .frame(height: (panel.cardSize.height * DetailsSheet.share).rounded())
    .background(CardBackground())
    .shadow(color: .black.opacity(0.5), radius: 17, y: -8)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .frame(maxHeight: .infinity, alignment: .bottom)
  }
}

/// The error of a failed save above Revert all, 🌐, Cancel and Save.
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
        if details.canLookUp {
          Button {
            details.lookUp()
          } label: {
            Image(systemName: "globe")
          }
          .buttonStyle(CircleButtonStyle())
          .help("Look up online (⌘L)")
          .accessibilityLabel("Look up online")
        }
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
struct KeyHintLabel: View {
  let title: String
  let key: String

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
      Text(key).font(.system(size: 10, weight: .semibold)).opacity(0.7)
    }
  }
}
