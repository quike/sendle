import AppKit
import SendleDomain
import SwiftUI

struct BookGrid: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 0) {
          BookCover(
            panel: panel, item: item, size: .large,
            showsFormat: panel.library.showsFormatOnCovers
          )
          .aspectRatio(2 / 3, contentMode: .fit)
          Text(item.title)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .padding(.top, 6)
          Text(item.byline)
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        .bookInteractions(panel, item)
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .scrollTargetLayout()
    .padding(.horizontal, 4)
  }
}

struct BookList: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    // Letter headers come with the full A–Z bar, as in Contacts.
    let headers = library.jumpBar == .full ? library.index : nil
    LazyVStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 2) {
          if let letter = headers?.header(before: item.id) {
            LetterHeader(letter: letter)
          }
          BookRow(panel: panel, item: item)
        }
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .scrollTargetLayout()
  }
}

private struct LetterHeader: View {
  let letter: String

  var body: some View {
    Text(letter)
      .font(.system(size: 10, weight: .bold))
      .kerning(0.8)
      .foregroundStyle(Theme.faint)
      .padding(.horizontal, 7)
      .padding(.top, 8)
      .padding(.bottom, 1)
      .accessibilityAddTraits(.isHeader)
  }
}

/// "Recently added" covers above the full list.
struct BookShelf: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  let recent: [BookItemViewModel]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionLabel("Recently added")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(recent) { item in
            BookCover(panel: panel, item: item, size: .large, titleSize: 8)
              .frame(width: 62, height: 93)
              .bookInteractions(panel, item)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
      }
      .scrollIndicators(.never)
      SectionLabel("All books").padding(.top, 6).padding(.bottom, 4)
      BookList(panel: panel, items: items)
    }
  }
}

struct BookRow: View {
  let panel: PanelModel
  let item: BookItemViewModel

  var body: some View {
    let library = panel.library
    let isSelected = library.selection.contains(item.id)
    let isHovered = library.hovered == item.id
    HStack(spacing: 10) {
      BookCover(panel: panel, item: item, size: .small, showsMarks: false)
        .frame(width: 34, height: 50)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
        Text(item.byline).font(.system(size: 10.5)).foregroundStyle(Theme.muted).lineLimit(1)
        HStack(spacing: 5) {
          FormatBadge(text: item.badge)
          ForEach(item.routes, id: \.self) { kind in
            Image(systemName: kind.symbol)
              .font(.system(size: 8.5))
              .foregroundStyle(Theme.tint(for: kind))
          }
          Text(item.detail).foregroundStyle(item.tone.color).lineLimit(1)
        }
        .font(.system(size: 9.5))
        .padding(.top, 2)
      }
      Spacer(minLength: 6)
      RowMark(panel: panel, item: item, isSelected: isSelected, isHovered: isHovered)
    }
    .padding(7)
    .background(
      isSelected
        ? Theme.tint(for: library.activeKind).opacity(0.14) : isHovered ? Theme.glass : .clear,
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .opacity(item.tone == .unavailable ? 0.5 : 1)
    .bookInteractions(panel, item)
  }
}

/// The round mark at the end of a row: selected, quick-send on hover, or why it can't go.
private struct RowMark: View {
  let panel: PanelModel
  let item: BookItemViewModel
  let isSelected: Bool
  let isHovered: Bool

  var body: some View {
    Group {
      if isSelected {
        Image(systemName: "checkmark").foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(Theme.tint(for: panel.library.activeKind), in: Circle())
      } else if !item.canSend {
        Image(systemName: blockedSymbol).foregroundStyle(Theme.faint).frame(width: 30, height: 30)
      } else {
        QuickSendButton(panel: panel, item: item, isProminent: isHovered)
      }
    }
    .font(.system(size: 12, weight: .semibold))
  }

  /// A lock only for books that are locked; the rest can't go to this destination.
  private var blockedSymbol: String {
    switch item.book.availability {
    case .inCloudOnly: "icloud"
    case .protected: "lock"
    case .ready, .missing: "nosign"
    }
  }
}

/// Sends one book to the active destination chip.
struct QuickSendButton: View {
  let panel: PanelModel
  let item: BookItemViewModel
  let isProminent: Bool

  var body: some View {
    let library = panel.library
    Button {
      panel.quickSend(item.id)
    } label: {
      Image(systemName: "paperplane.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isProminent ? .white : Color(hex: 0xc9d3ea))
        .frame(width: 28, height: 28)
        .background(
          isProminent
            ? AnyShapeStyle(Theme.action(for: library.activeKind)) : AnyShapeStyle(Theme.glass),
          in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(!library.canSend)
    .opacity(library.canSend ? 1 : 0.6)
    .help(library.quickSendHelp)
    .accessibilityLabel("Send")
  }
}

struct BookCover: View {
  let panel: PanelModel
  let book: Book
  /// Nil draws the cover alone: no selection, sent mark or quick-send.
  let item: BookItemViewModel?
  let size: CoverSize
  var titleSize: CGFloat = 10
  var showsFormat = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    panel: PanelModel,
    item: BookItemViewModel,
    size: CoverSize,
    showsMarks: Bool = true,
    titleSize: CGFloat = 10,
    showsFormat: Bool = false
  ) {
    self.panel = panel
    book = item.book
    self.item = showsMarks ? item : nil
    self.size = size
    self.titleSize = titleSize
    self.showsFormat = showsFormat
  }

  /// A book's cover where no destination applies, as in the queue.
  init(panel: PanelModel, book: Book, size: CoverSize) {
    self.panel = panel
    self.book = book
    item = nil
    self.size = size
  }

  var body: some View {
    let slot = panel.covers.slot(for: book, size: size)
    let isSelected = item.map { panel.library.selection.contains($0.id) } ?? false
    let isHovered = item.map { panel.library.hovered == $0.id } ?? false
    let isUnavailable = book.availability != .ready
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 7, topTrailingRadius: 7,
      style: .continuous)
    // The clear base takes the proposed size, so a cover of another shape can't widen the cell.
    Color.clear
      .overlay {
        if let data = slot.data, let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          TitleCardView(
            book: book, titleSize: size == .large ? titleSize : nil,
            bottomInset: showsFormat && item != nil ? 16 : 0)
        }
      }
      .clipShape(shape)
      .overlay(alignment: .leading) {
        Rectangle().fill(Color.black.opacity(0.18)).frame(width: 3)
      }
      .saturation(isUnavailable ? 0.2 : 1)
      .brightness(isUnavailable ? -0.3 : 0)
      .overlay {
        if book.availability == .protected {
          Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(.white)
        }
      }
      .overlay(alignment: .topTrailing) {
        if let routes = item?.routes, !routes.isEmpty {
          HStack(spacing: 2) {
            ForEach(routes, id: \.self) { kind in
              CoverMark(symbol: kind.symbol, color: Theme.tint(for: kind))
            }
          }
          .padding(5)
        }
      }
      .overlay(alignment: .topLeading) {
        if isSelected {
          CoverMark(symbol: "checkmark", color: Theme.tint(for: panel.library.activeKind))
            .padding(5)
        }
      }
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Theme.tint(for: panel.library.activeKind), lineWidth: 2)
            .padding(-4)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if showsFormat, let item { FormatBadge(text: item.badge, onCover: true).padding(6) }
      }
      .overlay(alignment: .bottomTrailing) {
        if isHovered, let item, item.canSend, size == .large {
          QuickSendButton(panel: panel, item: item, isProminent: true).padding(6)
        }
      }
      .shadow(color: .black.opacity(isHovered ? 0.6 : 0.45), radius: isHovered ? 12 : 8, y: 6)
      .scaleEffect(isHovered ? 1.03 : 1)
      .offset(y: isHovered ? -3 : 0)
      .animation(reduceMotion ? nil : Theme.press, value: isHovered)
      .task(id: book) { await panel.covers.load(book, size: size) }
      .accessibilityHidden(true)
  }
}

private struct CoverMark: View {
  let symbol: String
  let color: Color

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 8, weight: .heavy))
      .foregroundStyle(Theme.background)
      .frame(width: 16, height: 16)
      .background(color, in: Circle())
      .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
  }
}

/// A generated cover for books without one, in colours that stay put across launches.
struct TitleCardView: View {
  let book: Book
  /// Nil leaves the title off, for covers too small to read it.
  let titleSize: CGFloat?
  /// Room kept clear at the bottom, for what sits over the card.
  var bottomInset: CGFloat = 0

  var body: some View {
    let colors = Theme.coverGradients[
      TitleCard.paletteIndex(for: book.id, count: Theme.coverGradients.count)]
    LinearGradient(
      colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay(alignment: .bottomLeading) {
      if let titleSize {
        Text(book.title)
          .font(.custom("Georgia", size: titleSize))
          .foregroundStyle(Color.white.opacity(0.92))
          .lineLimit(4)
          .minimumScaleFactor(0.7)
          .padding(titleSize < 10 ? 5 : 7)
          .padding(.bottom, bottomInset)
      }
    }
  }
}

extension BookItemViewModel.Tone {
  var color: Color {
    switch self {
    case .plain, .unavailable: Theme.faint
    case .sent: Theme.muted
    case .warning: Theme.warm
    }
  }
}

extension ClickKind {
  /// ⇧ extends a range, ⌘ toggles one book, as in Finder.
  static var current: ClickKind {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { return .range }
    if flags.contains(.command) { return .toggle }
    return .plain
  }
}

extension View {
  /// Click to select, hover for quick-send: the same in every layout. VoiceOver reads one element
  /// per book, whose actions select it or send it.
  func bookInteractions(_ panel: PanelModel, _ item: BookItemViewModel) -> some View {
    let library = panel.library
    let details = [item.badge, item.detail, item.spokenRoutes ?? ""].filter { !$0.isEmpty }
    return contentShape(Rectangle())
      .onTapGesture { panel.click(item.id, .current) }
      .onHover { inside in
        if inside {
          library.hovered = item.id
        } else if library.hovered == item.id {
          library.hovered = nil
        }
      }
      .help(item.detail)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(item.title), \(item.byline)")
      .accessibilityValue(details.joined(separator: ", "))
      .accessibilityAddTraits(
        library.selection.contains(item.id) ? [.isButton, .isSelected] : .isButton
      )
      .accessibilityAction { panel.click(item.id, .plain) }
      .accessibilityActions {
        if item.canSend, library.canSend {
          Button("Send") { panel.quickSend(item.id) }
        }
      }
  }
}
