import SendleDomain
import SwiftUI

/// A Kindle book's details, read-only, in the edit sheet's frame. They are edited on the library
/// book it matches.
struct KindleDetailsSheet: View {
  let panel: PanelModel
  let details: KindleDetailsViewModel

  var body: some View {
    DetailsSheetFrame(panel: panel, label: "Kindle book details") {
      DetailsFactsRow(facts: details.facts) {
        KindleCover(kindle: panel.kindle, item: details.item, size: .large)
          .frame(width: 78, height: 117)
      }
      ReadOnlyField(label: "Title", value: details.title)
      ReadOnlyField(label: "Author", value: details.author)
      HStack(alignment: .top, spacing: 10) {
        ReadOnlyField(label: "Year", value: details.year).frame(width: 84)
        ReadOnlyField(label: "ISBN", value: details.isbn)
      }
      ReadOnlyField(label: "Language", value: details.language)
      ReadOnlyField(label: "Publisher", value: details.publisher)
      ReadOnlyField(label: "File", value: details.file)
      ReadOnlyField(label: "ASIN", value: details.asin)
      if let note = details.note {
        FieldNote(text: note).padding(.top, 12).padding(.horizontal, 2)
      }
    } actions: {
      KindleDetailsActions(panel: panel, details: details)
    } badge: {
      CoverMark(symbol: "ipad", color: Theme.live)
    }
  }
}

/// A value in the edit sheet's glass, which can be selected but not changed.
private struct ReadOnlyField: View {
  let label: String
  let value: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DetailsLabel(label)
      Text(value ?? "—")
        .font(.system(size: 12.5))
        .foregroundStyle(value == nil ? Theme.faint : Theme.text)
        .textSelection(.enabled)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailsField(isEdited: false)
    }
  }
}

/// Where the book is in the library, then Edit in Library when it can be edited there, and Done.
private struct KindleDetailsActions: View {
  let panel: PanelModel
  let details: KindleDetailsViewModel

  var body: some View {
    HStack(spacing: 8) {
      if let line = details.libraryLine {
        Text(line)
          .font(.system(size: 11))
          .foregroundStyle(Theme.muted)
          .lineLimit(1)
          .help(line)
      }
      Spacer(minLength: 0)
      if details.library?.canEdit == true {
        Button("Edit in Library") {
          Task { await panel.editInLibrary() }
        }
        .buttonStyle(SecondaryButtonStyle())
      }
      Button {
        panel.closeKindleDetails()
      } label: {
        KeyHintLabel(title: "Done", key: "esc")
      }
      .buttonStyle(PrimaryButtonStyle())
      .accessibilityLabel("Done")
    }
    .padding(.top, 8)
  }
}
