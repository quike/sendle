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

/// Why a delete failed, where the book is in the library, then Delete… on the left and Edit in
/// Library, when it can be edited there, and Done on the right; or the delete's question.
private struct KindleDetailsActions: View {
  let panel: PanelModel
  let details: KindleDetailsViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let isAsking = panel.removal.map { $0.stage != .idle } ?? false
    VStack(alignment: .leading, spacing: 6) {
      if let failure = panel.removal?.failure {
        FieldNote(text: failure, color: Theme.danger)
      }
      if let line = details.libraryLine {
        Text(line)
          .font(.system(size: 11))
          .foregroundStyle(Theme.muted)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .help(line)
      }
      if isAsking {
        DeleteQuestion(panel: panel, details: details).transition(.opacity)
      } else {
        buttons.transition(.opacity)
      }
    }
    .padding(.top, 8)
    .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: isAsking)
  }

  private var buttons: some View {
    HStack(spacing: 8) {
      if panel.removal != nil {
        Button("Delete…") {
          panel.askToDeleteKindleBook()
        }
        .buttonStyle(DangerButtonStyle())
        .disabled(!panel.canDeleteKindleBook)
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
  }
}

/// The red strip the actions row turns into: the question, what goes with the book, Cancel and
/// Delete. Its buttons wait while the delete is made.
private struct DeleteQuestion: View {
  let panel: PanelModel
  let details: KindleDetailsViewModel

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    VStack(alignment: .leading, spacing: 3) {
      Text(details.deleteQuestion)
        .font(.system(size: 12, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
      Text(details.deleteDetail)
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button {
          panel.cancelKindleDelete()
        } label: {
          KeyHintLabel(title: "Cancel", key: "esc")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel("Cancel")
        Button {
          Task { await panel.deleteKindleBook() }
        } label: {
          KeyHintLabel(title: "Delete", key: "↩")
        }
        .buttonStyle(DangerSolidButtonStyle())
        .accessibilityLabel("Delete")
      }
      .padding(.top, 5)
      .disabled(panel.removal?.stage != .confirming)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.danger.opacity(0.08), in: shape)
    .overlay(shape.strokeBorder(Theme.danger.opacity(0.3)))
    .accessibilityElement(children: .contain)
  }
}
