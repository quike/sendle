import SendleDomain
import SwiftUI

/// Where the found details came from and how many differ, or how the lookup went. Its source's
/// name opens a menu of every source asked, to show another's details.
struct LookupBannerView: View {
  let panel: PanelModel
  let details: BookDetailsViewModel
  let banner: LookupBanner

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
    HStack(spacing: 8) {
      Text("🌐").accessibilityHidden(true)
      switch banner {
      case .found(let source, let differences):
        HStack(spacing: 5) {
          sourceMenu(source)
          if source == .googleBooks, let link = details.shownEdition?.link {
            Button("↗") { Task { await panel.perform(.openURL(link)) } }
              .buttonStyle(.plain)
              .fontWeight(.semibold)
              .foregroundStyle(Theme.link)
              .help("Open on Google Books")
              .accessibilityLabel("Open on Google Books")
          }
          tally(differences)
        }
        Spacer(minLength: 4)
        if differences > 0 {
          Button("Use all") { details.useAll() }
            .buttonStyle(FoundButtonStyle())
            .disabled(!hasUnusedValues)
        }
      case .editions(let source, _):
        sourceMenu(source)
        Spacer(minLength: 0)
      case .searching:
        Text(banner.text)
        Spacer(minLength: 4)
        ProgressView().controlSize(.small)
      case .allAgree, .nothingFound, .offline, .unreachable:
        Text(banner.text).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
    }
    .font(.system(size: 11.5))
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(minHeight: 32)
    .background(Theme.accent.opacity(0.1), in: shape)
    .overlay(shape.strokeBorder(Theme.accent.opacity(0.25)))
    .accessibilityElement(children: .contain)
  }

  /// The banner's words, with the source's name in link blue and a ▾ that opens the menu.
  private func sourceMenu(_ source: LookupSource) -> some View {
    Menu {
      ForEach(details.sourceMenu, id: \.source) { entry in
        Button {
          details.show(entry.source)
        } label: {
          let title = "\(entry.source.name) — \(entry.status)"
          if entry.source == details.shownSource {
            Label(title, systemImage: "checkmark")
          } else {
            Text(title)
          }
        }
        .disabled(!canShow(entry.source))
      }
    } label: {
      sentence(naming: source)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .help("Show another source's details")
    .accessibilityLabel(banner.text)
    .accessibilityHint("Shows another source's details")
  }

  private func sentence(naming source: LookupSource) -> Text {
    let text = banner.text
    let name = Text("\(source.name) ▾").fontWeight(.semibold).foregroundStyle(Theme.link)
    guard let range = text.range(of: source.name) else { return Text("\(Text(text)) \(name)") }
    return Text(
      "\(Text(text[..<range.lowerBound]))\(name)\(Text(text[range.upperBound...]))")
  }

  /// "· 3 differences", or "· Agrees with everything" when there are none.
  private func tally(_ differences: Int) -> some View {
    let count =
      switch differences {
      case 0: "Agrees with everything"
      case 1: "1 difference"
      default: "\(differences) differences"
      }
    return Text("· \(Text(count).fontWeight(.semibold))")
      .lineLimit(1)
      .accessibilityLabel(count)
  }

  /// A source still asking, or without details, can't be shown.
  private func canShow(_ source: LookupSource) -> Bool {
    switch details.progress?.result(for: source) {
    case .edition?, .editions?: true
    case .asking?, .notFound?, .failed?, nil: false
    }
  }

  private var hasUnusedValues: Bool {
    BookDetailsViewModel.Field.allCases.contains { field in
      if case .differs? = details.found(field) { true } else { false }
    }
  }
}

/// Under a compared field: the shown edition's value with Use, or, once used, what the field held
/// with Undo. Nothing when the values match or the edition has none.
struct FoundBubble: View {
  /// The field's name in VoiceOver's labels, such as "title".
  let name: String
  let details: BookDetailsViewModel
  let field: BookDetailsViewModel.Field

  var body: some View {
    switch details.found(field) {
    case .differs(let text)?:
      bubble(key: "Found", value: text, color: Theme.text) {
        Button("Use") { details.use(field) }
          .buttonStyle(FoundButtonStyle())
          .accessibilityLabel("Use found \(name): \(text)")
      }
    case .used(let was)?:
      bubble(key: "Was", value: was, color: Theme.muted) {
        Button("Undo") { details.undo(field) }
          .buttonStyle(FoundButtonStyle(isProminent: false))
          .accessibilityLabel("Undo \(name)")
      }
    case .matches?, nil:
      EmptyView()
    }
  }

  private func bubble(
    key: String, value: String, color: Color, @ViewBuilder action: () -> some View
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
    return HStack(spacing: 7) {
      Text(key.uppercased())
        .font(.system(size: 9.5, weight: .bold))
        .kerning(0.6)
        .foregroundStyle(Theme.link)
        .fixedSize()
      Text(value)
        .font(.system(size: 11.5))
        .foregroundStyle(color)
        .lineLimit(2)
        .help(value)
        .frame(maxWidth: .infinity, alignment: .leading)
      action()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Theme.accent.opacity(0.1), in: shape)
    .overlay(shape.strokeBorder(Theme.accent.opacity(0.28)))
    .padding(.top, 4)
  }
}

/// "matches", quietly at a field's trailing edge, when the found value is the field's.
struct FoundMatch: View {
  let found: FoundValue?

  var body: some View {
    if found == .matches {
      Text("matches")
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.faint)
        .fixedSize()
    }
  }
}

/// The sheet's cover → the shown edition's, with its size and Use cover, or Undo once used.
struct FoundCoverRow: View {
  let panel: PanelModel
  let details: BookDetailsViewModel
  let cover: FoundCover

  var body: some View {
    let book = details.coverBook
    let slot = panel.covers.slot(for: book, size: .large)
    // Once used, the found cover is the sheet's, so the book's own stands for the one it replaced.
    let current = details.isFoundCoverUsed ? nil : details.coverPreview
    HStack(alignment: .bottom, spacing: 12) {
      HStack(spacing: 10) {
        CoverFace(
          data: current ?? slot.data, isPending: current == nil && slot.isPending,
          title: book.title, seed: book.id, titleSize: 9
        )
        .frame(width: 60, height: 90)
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.faint)
        CoverFace(data: cover.file.preview, title: book.title, seed: book.id, titleSize: 9)
          .frame(width: 60, height: 90)
      }
      .shadow(color: .black.opacity(0.6), radius: 7, y: 6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Found cover, \(cover.sizeText)")
      VStack(alignment: .leading, spacing: 6) {
        Text(cover.sizeText)
          .font(.system(size: 11))
          .foregroundStyle(Theme.muted)
          .accessibilityHidden(true)
        if details.isFoundCoverUsed {
          Button("Undo") { details.undoFoundCover() }
            .buttonStyle(FoundButtonStyle(isProminent: false))
            .accessibilityLabel("Undo cover")
        } else {
          Button("Use cover") { details.useFoundCover() }
            .buttonStyle(FoundButtonStyle())
            .accessibilityLabel("Use found cover")
        }
      }
      Spacer(minLength: 0)
    }
    .task(id: book) { await panel.covers.load(book, size: .large) }
  }
}

/// The editions a search by title and author found at the shown source, to pick the book's from.
struct EditionList: View {
  let details: BookDetailsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Which edition is yours?")
        .font(.system(size: 14, weight: .semibold))
        .accessibilityAddTraits(.isHeader)
      FieldNote(text: "The date and cover come from the edition you pick.")
        .padding(.top, 2)
      VStack(spacing: 6) {
        ForEach(details.editionRows) { row in
          EditionRowView(
            row: row, thumbnail: row.edition.thumbnail.flatMap { details.thumbnails[$0] }
          ) {
            details.pick(row)
          }
        }
      }
      // A row's id is its place, so another source's list starts afresh.
      .id(details.shownSource)
      .padding(.top, 10)
    }
  }
}

private struct EditionRowView: View {
  let row: EditionRow
  let thumbnail: Data?
  let pick: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      cover
      VStack(alignment: .leading, spacing: 2) {
        Text(row.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
        Text(row.detail).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
        if let identifiers = row.identifiers {
          Text(identifiers).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 6)
      Button("This one", action: pick).buttonStyle(FoundButtonStyle())
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .glass(cornerRadius: 12)
    .accessibilityElement(children: .contain)
  }

  /// The edition's thumbnail, or a plain tile until it comes or when there is none.
  private var cover: some View {
    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
    return Group {
      if let thumbnail, let image = NSImage(data: thumbnail) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Theme.glassHigh.overlay {
          Image(systemName: "book.closed")
            .font(.system(size: 12))
            .foregroundStyle(Theme.faint)
        }
      }
    }
    .frame(width: 32, height: 48)
    .clipShape(shape)
    .shadow(color: .black.opacity(0.6), radius: 5, y: 4)
    .accessibilityHidden(true)
  }
}

/// "None of these" and Skip, which both go back to the sheet as it was.
struct EditionListActions: View {
  let details: BookDetailsViewModel

  var body: some View {
    HStack(spacing: 8) {
      Button("None of these") { details.skipEditionList() }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.link)
      Spacer(minLength: 0)
      Button {
        details.skipEditionList()
      } label: {
        KeyHintLabel(title: "Skip", key: "esc")
      }
      .buttonStyle(SecondaryButtonStyle())
      .accessibilityLabel("Skip")
    }
    // As tall as the sheet's own actions, so the content above doesn't move.
    .frame(minHeight: 34)
    .padding(.top, 8)
  }
}

/// The small pill of Use, Use all, Use cover and This one; Undo's is quieter.
private struct FoundButtonStyle: ButtonStyle {
  var isProminent = true
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    configuration.label
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(isProminent ? Color.white : Theme.link)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(isProminent ? Theme.accent : Theme.link.opacity(0.14), in: shape)
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
      .contentShape(shape)
      .fixedSize()
  }
}
