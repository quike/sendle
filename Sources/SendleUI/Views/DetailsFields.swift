import SendleDomain
import SwiftUI

/// The edit sheet's fields: title and author with their sort lines, then year, ISBN and
/// language, which a PDF's file doesn't hold.
struct DetailsFields: View {
  @Bindable var details: BookDetailsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DetailsLabel("Title")
      DetailsField(label: "Title", text: $details.title, details: details, field: .title)
      if details.showsSortTitle {
        SortLine(
          label: "Sort title", text: $details.sortTitle, isEditing: $details.isEditingSortTitle,
          showsField: details.showsSortTitleField, details: details, field: .sortTitle)
      }
      DetailsLabel("Author")
      DetailsField(label: "Author", text: $details.author, details: details, field: .author)
      if details.showsSortName {
        SortLine(
          label: "Sort name", text: $details.sortName, isEditing: $details.isEditingSortName,
          showsField: details.showsSortNameField, details: details, field: .sortName)
      }
      if details.showsWriterCheckbox {
        Toggle(details.writerCheckboxTitle, isOn: $details.changesWriter)
          .toggleStyle(.checkbox)
          .font(.system(size: 11))
          .padding(.top, 6)
          .padding(.horizontal, 2)
      }
      if details.isPDF {
        FieldNote(
          text: "A PDF's cover is its first page. Its title and author go in the file's name."
        )
        .padding(.top, 12)
        .padding(.horizontal, 2)
      } else {
        EditionFields(details: details)
        DetailsLabel("Language")
        LanguageField(details: details)
        if let warning = details.languageWarning {
          FieldNote(text: warning, color: Theme.warm).padding(.top, 4).padding(.horizontal, 2)
        }
      }
    }
  }
}

/// Year and ISBN side by side; the ISBN is checked as it is typed, without blocking Save.
private struct EditionFields: View {
  @Bindable var details: BookDetailsViewModel

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 0) {
        DetailsLabel("Year")
        DetailsField(label: "Year", text: $details.year, details: details, field: .year)
      }
      .frame(width: 84)
      VStack(alignment: .leading, spacing: 0) {
        DetailsLabel("ISBN")
        DetailsField(label: "ISBN", text: $details.isbn, details: details, field: .isbn) {
          if details.isbnStatus == .valid {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Theme.live)
              .accessibilityLabel("Valid ISBN")
          }
        }
        if let warning = isbnWarning {
          FieldNote(text: warning, color: Theme.warm)
            .padding(.top, 4)
            .padding(.horizontal, 2)
        }
      }
    }
  }

  private var isbnWarning: String? {
    switch details.isbnStatus {
    case .empty, .valid: nil
    case .wrongCheckDigit: "Check digit doesn't match"
    case .notAnISBN: "Not a valid ISBN"
    }
  }
}

/// "Sorted as … Edit" under the title or the author. Edit turns it into a field, as an edit does.
private struct SortLine: View {
  let label: String
  @Binding var text: String
  @Binding var isEditing: Bool
  let showsField: Bool
  let details: BookDetailsViewModel
  let field: BookDetailsViewModel.Field

  var body: some View {
    HStack(spacing: 6) {
      Text("Sorted as").foregroundStyle(Theme.muted)
      if showsField {
        DetailsField(
          label: label, text: $text, details: details, field: field, focusesOnAppear: isEditing)
      } else {
        Text(text.isEmpty ? details.placeholder(field) : text)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)
        Button("Edit") { isEditing = true }
          .buttonStyle(.plain)
          .fontWeight(.semibold)
          .foregroundStyle(Theme.link)
          .accessibilityLabel("Edit \(label.lowercased())")
      }
    }
    .font(.system(size: 10.5))
    .padding(.top, 5)
    .padding(.horizontal, showsField ? 0 : 2)
  }
}

/// Amazon's languages by name, then "Other…", which shows a field for any tag beside the pop-up.
private struct LanguageField: View {
  @Bindable var details: BookDetailsViewModel

  var body: some View {
    let marksEdit = details.isEdited(.language) && !details.isTypingLanguage
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        Menu {
          ForEach(details.languages, id: \.tag) { entry in
            choice(entry.name, isChosen: details.isChosenLanguage(entry.tag)) {
              details.chooseLanguage(entry.tag)
            }
          }
          Divider()
          choice("Other…", isChosen: details.isTypingLanguage) { details.typeOtherLanguage() }
        } label: {
          HStack(spacing: 6) {
            Text(details.languageTitle).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(Theme.faint)
          }
          .font(.system(size: 12.5))
          .foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, minHeight: 28)
          .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Language")
        .accessibilityValue(details.languageTitle)
        if marksEdit {
          RevertButton(help: details.revertHelp(.language), label: "Revert language") {
            details.revert(.language)
          }
        }
      }
      .detailsField(isEdited: marksEdit)
      if details.isTypingLanguage {
        DetailsField(
          label: "Language tag", text: $details.typedLanguage, details: details, field: .language,
          prompt: "Tag, like pt-BR", focusesOnAppear: true)
      }
    }
  }

  @ViewBuilder
  private func choice(
    _ title: String, isChosen: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      if isChosen {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }
}

/// A field's name above it, as the mockup's small capitals.
private struct DetailsLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    SectionLabel(text).padding(.top, 8).padding(.bottom, 3)
  }
}

/// A text field of the sheet. Emptied, it shows what it goes back to; edited, it gets a warm
/// border and a ↺ that reverts it.
private struct DetailsField<Accessory: View>: View {
  let label: String
  @Binding var text: String
  let details: BookDetailsViewModel
  let field: BookDetailsViewModel.Field
  var prompt: String?
  /// Takes the keyboard when it appears, as a field just asked for does.
  var focusesOnAppear = false
  @ViewBuilder let accessory: Accessory
  @FocusState private var isFocused: Bool

  var body: some View {
    let isEdited = details.isEdited(field)
    HStack(spacing: 6) {
      TextField(
        label, text: $text,
        prompt: Text(prompt ?? details.placeholder(field)).foregroundStyle(Theme.faint)
      )
      .labelsHidden()
      .textFieldStyle(.plain)
      .font(.system(size: 12.5))
      .focused($isFocused)
      .onAppear { if focusesOnAppear { isFocused = true } }
      .accessibilityLabel(label)
      accessory
      if isEdited {
        RevertButton(help: details.revertHelp(field), label: "Revert \(label.lowercased())") {
          details.revert(field)
        }
      }
    }
    .detailsField(isEdited: isEdited)
  }
}

extension DetailsField where Accessory == EmptyView {
  init(
    label: String, text: Binding<String>, details: BookDetailsViewModel,
    field: BookDetailsViewModel.Field, prompt: String? = nil, focusesOnAppear: Bool = false
  ) {
    self.init(
      label: label, text: text, details: details, field: field, prompt: prompt,
      focusesOnAppear: focusesOnAppear, accessory: { EmptyView() })
  }
}

/// The ↺ inside an edited field; its tooltip names the value it puts back.
private struct RevertButton: View {
  let help: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.uturn.backward")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Theme.link)
        .frame(width: 20, height: 20)
        .background(Theme.link.opacity(0.14), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(label)
  }
}

extension View {
  /// The glass of `GlassTextField`, a little denser, with a warm border once edited.
  fileprivate func detailsField(isEdited: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    return padding(.leading, 10)
      .padding(.trailing, isEdited ? 4 : 10)
      .frame(minHeight: 28)
      .glass(cornerRadius: 10)
      .overlay {
        if isEdited { shape.strokeBorder(Theme.warm.opacity(0.45)) }
      }
  }
}
