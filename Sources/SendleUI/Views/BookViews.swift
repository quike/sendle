import AppKit
import SendleDomain
import SwiftUI

/// The grid's columns and rows, shared by the library's and the Kindle's books and their skeleton.
package enum BookGridMetrics {
  package static let columns = 3
  package static let columnSpacing: CGFloat = 10
  package static let rowSpacing: CGFloat = 12
  /// Between a cover and its title.
  package static let titleGap: CGFloat = 6
  package static let titleHeight: CGFloat = 13
  package static let bylineHeight: CGFloat = 12

  /// A row in a grid `width` wide: a 2:3 cover as wide as a column, its title and its byline.
  package static func rowHeight(width: CGFloat) -> CGFloat {
    let gaps = columnSpacing * CGFloat(columns - 1)
    let column = (width - gaps) / CGFloat(columns)
    return column * 3 / 2 + titleGap + titleHeight + bylineHeight
  }
}

let bookGridColumns = Array(
  repeating: GridItem(.flexible(), spacing: BookGridMetrics.columnSpacing, alignment: .top),
  count: BookGridMetrics.columns)

/// A grid book's title and byline under its cover, at the rows' heights.
struct GridCaption: View {
  let title: String
  let byline: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 10.5, weight: .semibold))
        .lineLimit(1)
        .frame(height: BookGridMetrics.titleHeight)
      Text(byline)
        .font(.system(size: 9.5))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .frame(height: BookGridMetrics.bylineHeight)
    }
    .padding(.top, BookGridMetrics.titleGap)
  }
}

struct BookGrid: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    LazyVGrid(
      columns: bookGridColumns, alignment: .leading, spacing: BookGridMetrics.rowSpacing
    ) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 0) {
          BookCover(
            panel: panel, item: item, size: .large,
            showsFormat: panel.library.showsFormatOnCovers
          )
          .aspectRatio(2 / 3, contentMode: .fit)
          GridCaption(title: item.title, byline: item.byline)
        }
        .bookInteractions(panel, item)
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .scrollTargetLayout()
    .padding(.horizontal, BooksArea.gridInset)
  }
}

struct BookList: View {
  let panel: PanelModel
  let items: [BookItemViewModel]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    // Letter headers come with the full A–Z bar, as in Contacts.
    let headers = library.jumpBar == .full ? library.letterJump.index : nil
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

struct LetterHeader: View {
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
      // Not past the trailing edge, which keeps the A–Z bar's gutter.
      .scrollOverflow([.vertical, .leading])
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
          ForEach(item.marks, id: \.self) { mark in
            Image(systemName: mark.rowSymbol)
              .font(.system(size: 8.5))
              .foregroundStyle(mark.color)
              .opacity(mark.opacity)
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
      Task { await panel.quickSend(item.id) }
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
  /// Marked with a pencil, even where the sent marks are left out.
  let isEdited: Bool
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
    isEdited = item.isEdited
    self.item = showsMarks ? item : nil
    self.size = size
    self.titleSize = titleSize
    self.showsFormat = showsFormat
  }

  /// A book's cover where no destination applies, as in the queue.
  init(panel: PanelModel, book: Book, size: CoverSize) {
    self.panel = panel
    self.book = book
    isEdited = false
    item = nil
    self.size = size
  }

  var body: some View {
    let slot = panel.covers.slot(for: book, size: size)
    let isSelected = item.map { panel.library.selection.contains($0.id) } ?? false
    let isHovered = item.map { panel.library.hovered == $0.id } ?? false
    let look = CoverLook.of(book.availability)
    CoverFace(
      data: slot.data, isPending: slot.isPending, title: book.title, seed: book.id,
      titleSize: size == .large ? titleSize : nil,
      bottomInset: showsFormat && item != nil ? 16 : 0
    )
    .saturation(look.saturation)
    .brightness(look.brightness)
    .overlay {
      if book.availability == .protected {
        Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(.white)
      }
    }
    .overlay(alignment: .topTrailing) {
      let marks = item?.marks ?? []
      if isEdited || !marks.isEmpty {
        HStack(spacing: 2) {
          if isEdited { EditedMark() }
          ForEach(marks, id: \.self) { BookMarkView(mark: $0) }
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
      if look.showsCloud, size == .large {
        CoverMark(symbol: "icloud.fill", color: Theme.muted).padding(5)
      }
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

/// A cover's picture, or a title card where there is none, with its rounded corners and spine. A
/// cover still being read shows a skeleton, and the picture fades in over it.
struct CoverFace: View {
  static let shape = UnevenRoundedRectangle(
    topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 7, topTrailingRadius: 7,
    style: .continuous)

  let data: Data?
  var isPending = false
  let title: String
  let seed: BookID
  let titleSize: CGFloat?
  var bottomInset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // The clear base takes the proposed size, so a cover of another shape can't widen the cell.
    Color.clear
      .overlay {
        Group {
          if isPending {
            ShimmerFill().transition(.opacity)
          } else if let data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
          } else {
            TitleCardView(
              title: title, seed: seed, titleSize: titleSize, bottomInset: bottomInset
            )
            .transition(.opacity)
          }
        }
        .animation(reduceMotion ? nil : Theme.press, value: isPending)
      }
      .clipShape(Self.shape)
      .overlay(alignment: .leading) { CoverSpine() }
  }
}

struct CoverSpine: View {
  var body: some View {
    Rectangle().fill(Color.black.opacity(0.18)).frame(width: 3)
  }
}

/// A mark's symbol, stretched into the even-sided box nearest its own shape, so it sits on whole
/// pixels in the middle of a 16 pt mark at 1x as at 2x.
package struct MarkGlyph: View {
  let symbol: String
  var side: CGFloat = 8

  package var body: some View {
    let size = Self.size(of: symbol, within: side)
    Image(systemName: symbol)
      .resizable()
      .fontWeight(.heavy)
      .frame(width: size.width, height: size.height)
  }

  private static var sizes: [String: CGSize] = [:]

  package static func size(of symbol: String, within side: CGFloat) -> CGSize {
    let key = "\(symbol)@\(side)"
    if let size = sizes[key] { return size }
    let natural =
      NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.size
      ?? CGSize(width: side, height: side)
    let size = size(natural: natural, within: side)
    sizes[key] = size
    return size
  }

  /// A tall or wide symbol stays so even when its shorter side would round up to the longer.
  package static func size(natural: CGSize, within side: CGFloat) -> CGSize {
    let scale = side / max(natural.width, natural.height)
    func even(_ length: CGFloat) -> CGFloat { max(2, (length * scale / 2).rounded() * 2) }
    var size = CGSize(width: even(natural.width), height: even(natural.height))
    if natural.width < natural.height, size.width >= size.height {
      size.width = max(2, size.height - 2)
    } else if natural.height < natural.width, size.height >= size.width {
      size.height = max(2, size.width - 2)
    }
    return size
  }
}

struct CoverMark: View {
  let symbol: String
  let color: Color

  var body: some View {
    MarkGlyph(symbol: symbol)
      .foregroundStyle(Theme.background)
      .frame(width: 16, height: 16)
      .background(color, in: Circle())
      .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
  }
}

/// A rounded square, so its pencil doesn't read as a "no entry" sign the way it does in a circle.
struct EditedMark: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
    MarkGlyph(symbol: "pencil.line", side: 10)
      .foregroundStyle(Theme.background)
      .frame(width: 16, height: 16)
      .background(Theme.warm, in: shape)
      .overlay(shape.strokeBorder(Theme.background, lineWidth: 2))
  }
}

/// A mark on a cover: the route a book went by, or that the Kindle holds it, surely or maybe.
private struct BookMarkView: View {
  let mark: BookMark

  var body: some View {
    Group {
      if mark == .maybeOnKindle {
        MarkGlyph(symbol: mark.symbol)
          .foregroundStyle(mark.color)
          .frame(width: 16, height: 16)
          .background(Theme.background, in: Circle())
          .overlay(Circle().strokeBorder(mark.color, lineWidth: 1.5))
      } else {
        CoverMark(symbol: mark.symbol, color: mark.color)
      }
    }
    .opacity(mark.opacity)
  }
}

extension BookMark {
  var color: Color {
    switch self {
    case .route(let kind, _): Theme.tint(for: kind)
    case .onKindle, .maybeOnKindle: Theme.live
    }
  }

  /// The cover draws the maybe mark's circle itself; a row's icon needs it in the symbol.
  var rowSymbol: String { self == .maybeOnKindle ? "questionmark.circle" : symbol }

  /// A USB send the Kindle no longer shows.
  var opacity: Double {
    if case .route(_, dimmed: true) = self { 0.45 } else { 1 }
  }
}

/// A generated cover for books without one, in colours that stay put across launches.
struct TitleCardView: View {
  let title: String
  /// Picks the colours.
  let seed: BookID
  /// Nil leaves the title off, for covers too small to read it.
  let titleSize: CGFloat?
  /// Room kept clear at the bottom, for what sits over the card.
  var bottomInset: CGFloat = 0

  init(title: String, seed: BookID, titleSize: CGFloat?, bottomInset: CGFloat = 0) {
    self.title = title
    self.seed = seed
    self.titleSize = titleSize
    self.bottomInset = bottomInset
  }

  init(book: Book, titleSize: CGFloat?, bottomInset: CGFloat = 0) {
    self.init(
      title: book.title, seed: book.id, titleSize: titleSize, bottomInset: bottomInset)
  }

  var body: some View {
    let colors = Theme.coverGradients[
      TitleCard.paletteIndex(for: seed, count: Theme.coverGradients.count)]
    LinearGradient(
      colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .overlay(alignment: .bottomLeading) {
      if let titleSize {
        Text(title)
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
    let details = [
      item.badge, item.detail, item.spokenRoutes ?? "", item.spokenEdit ?? "",
      item.kindleText ?? "",
    ].filter { !$0.isEmpty }
    let helpLines = [
      item.detail, item.kindleText ?? "",
      item.isEdited ? "Edited in Sendle. Send again to update your Kindle." : "",
    ]
    return contentShape(Rectangle())
      .onTapGesture { panel.click(item.id, .current) }
      .onHover { inside in
        if inside {
          library.hovered = item.id
        } else if library.hovered == item.id {
          library.hovered = nil
        }
      }
      .help(helpLines.filter { !$0.isEmpty }.joined(separator: "\n"))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(item.title), \(item.byline)")
      .accessibilityValue(details.joined(separator: ", "))
      .accessibilityAddTraits(
        library.selection.contains(item.id) ? [.isButton, .isSelected] : .isButton
      )
      .accessibilityAction { panel.click(item.id, .plain) }
      .accessibilityActions {
        if item.canSend, library.canSend {
          Button("Send") { Task { await panel.quickSend(item.id) } }
        }
      }
      .contextMenu {
        Button("Edit Details…") { Task { await panel.openDetails(item.id) } }
          .disabled(!panel.canEditDetails(item.book))
      }
  }
}
