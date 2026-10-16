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
          BookCover(panel: panel, item: item, size: .large)
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
        .bookInteractions(panel.library, item)
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .padding(.horizontal, 4)
  }
}

struct BookList: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    LazyVStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        BookRow(panel: panel, item: item)
          .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
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
              .bookInteractions(panel.library, item)
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
          Text(item.detail).foregroundStyle(item.tone.color).lineLimit(1)
        }
        .font(.system(size: 9.5))
        .padding(.top, 2)
      }
      Spacer(minLength: 6)
      RowMark(item: item, isSelected: isSelected, isHovered: isHovered, hint: library.sendHint)
    }
    .padding(7)
    .background(
      isSelected ? Theme.accent.opacity(0.14) : isHovered ? Theme.glass : .clear,
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .opacity(item.tone == .unavailable ? 0.5 : 1)
    .bookInteractions(library, item)
  }
}

/// The round mark at the end of a row: selected, quick-send on hover, or why it can't go.
private struct RowMark: View {
  let item: BookItemViewModel
  let isSelected: Bool
  let isHovered: Bool
  let hint: String

  var body: some View {
    Group {
      if isSelected {
        Image(systemName: "checkmark").foregroundStyle(.white)
          .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
      } else if !item.canSend {
        Image(systemName: item.book.availability == .inCloudOnly ? "icloud" : "lock")
          .foregroundStyle(Theme.faint).frame(width: 30, height: 30)
      } else {
        QuickSendButton(isProminent: isHovered, hint: hint)
      }
    }
    .font(.system(size: 12, weight: .semibold))
  }
}

/// Sends one book to the active destination. Disabled until email sending exists.
struct QuickSendButton: View {
  let isProminent: Bool
  let hint: String

  var body: some View {
    Button {
    } label: {
      Image(systemName: "paperplane.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isProminent ? .white : Color(hex: 0xc9d3ea))
        .frame(width: 28, height: 28)
        .background(
          isProminent ? AnyShapeStyle(Theme.action) : AnyShapeStyle(Theme.glass), in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(true)
    .opacity(0.6)
    .help(hint)
    .accessibilityLabel("Send")
  }
}

struct BookCover: View {
  let panel: PanelModel
  let item: BookItemViewModel
  let size: CoverSize
  var showsMarks = true
  var titleSize: CGFloat = 10
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let slot = panel.covers.slot(for: item.book, size: size)
    let isSelected = showsMarks && panel.library.selection.contains(item.id)
    let isHovered = showsMarks && panel.library.hovered == item.id
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 7, topTrailingRadius: 7,
      style: .continuous)
    // The clear base takes the proposed size, so a cover of another shape can't widen the cell.
    Color.clear
      .overlay {
        if let data = slot.data, let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          TitleCardView(item: item, titleSize: size == .large ? titleSize : nil)
        }
      }
      .clipShape(shape)
      .overlay(alignment: .leading) {
        Rectangle().fill(Color.black.opacity(0.18)).frame(width: 3)
      }
      .saturation(item.tone == .unavailable ? 0.2 : 1)
      .brightness(item.tone == .unavailable ? -0.3 : 0)
      .overlay {
        if item.book.availability == .protected {
          Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(.white)
        }
      }
      .overlay(alignment: .topTrailing) {
        if showsMarks, item.tone == .sent { CoverMark(symbol: "checkmark", color: Theme.live) }
      }
      .overlay(alignment: .topLeading) {
        if isSelected { CoverMark(symbol: "checkmark", color: Theme.accent) }
      }
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .padding(-4)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isHovered, item.canSend, size == .large {
          QuickSendButton(isProminent: true, hint: panel.library.sendHint).padding(6)
        }
      }
      .shadow(color: .black.opacity(isHovered ? 0.6 : 0.45), radius: isHovered ? 12 : 8, y: 6)
      .scaleEffect(isHovered ? 1.03 : 1)
      .offset(y: isHovered ? -3 : 0)
      .animation(reduceMotion ? nil : Theme.press, value: isHovered)
      .task(id: item.book) { await panel.covers.load(item.book, size: size) }
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
      .padding(5)
  }
}

/// A generated cover for books without one, in colours that stay put across launches.
struct TitleCardView: View {
  let item: BookItemViewModel
  /// Nil leaves the title off, for covers too small to read it.
  let titleSize: CGFloat?

  var body: some View {
    let colors = Theme.coverGradients[
      TitleCard.paletteIndex(for: item.id, count: Theme.coverGradients.count)]
    LinearGradient(
      colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay(alignment: .bottomLeading) {
      if let titleSize {
        Text(item.title)
          .font(.custom("Georgia", size: titleSize))
          .foregroundStyle(Color.white.opacity(0.92))
          .lineLimit(4)
          .minimumScaleFactor(0.7)
          .padding(titleSize < 10 ? 5 : 7)
      }
    }
  }
}

extension BookItemViewModel.Tone {
  var color: Color {
    switch self {
    case .plain, .unavailable: Theme.faint
    case .sent: Theme.live
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
  /// Click to select, hover for quick-send: the same in every layout.
  func bookInteractions(_ library: LibraryViewModel, _ item: BookItemViewModel) -> some View {
    contentShape(Rectangle())
      .onTapGesture { library.click(item.id, .current) }
      .onHover { inside in
        if inside {
          library.hovered = item.id
        } else if library.hovered == item.id {
          library.hovered = nil
        }
      }
      .help(item.detail)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(
        library.selection.contains(item.id) ? [.isButton, .isSelected] : .isButton)
  }
}
