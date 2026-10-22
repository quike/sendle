import SendleDomain
import SwiftUI

/// The rows the library screen stacks above the books, and the gaps above each.
package enum LibraryControls {
  package static let header: CGFloat = 34
  /// Library | On Kindle, while a Kindle is plugged in.
  package static let sideSwitch: CGFloat = 26
  package static let sideSwitchGap: CGFloat = 12
  package static let chips: CGFloat = 26
  package static let search: CGFloat = 31
  package static let searchGap: CGFloat = 10
  package static let filterGap: CGFloat = 9
  package static let scopes: CGFloat = 21
  /// Between the scopes and the menus under them.
  package static let filterSpacing: CGFloat = 8
  package static let menus: CGFloat = 24

  /// Closer under the side switch than under the header.
  package static func chipsGap(withKindle: Bool) -> CGFloat { withKindle ? 8 : 12 }

  /// From the header's top to the menus' bottom.
  package static func height(withKindle: Bool) -> CGFloat {
    let side = withKindle ? sideSwitchGap + sideSwitch : 0
    let filter = filterGap + scopes + filterSpacing + menus
    return header + side + chipsGap(withKindle: withKindle) + chips + searchGap + search + filter
  }
}

struct LibraryScreen: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    let isKindleSide = panel.side == .kindle
    VStack(alignment: .leading, spacing: 0) {
      PanelHeader(title: "Sendle", subtitle: subtitle) {
        if isKindleSide {
          Button {
            Task { await panel.kindle.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(CircleButtonStyle())
          .help("Refresh (⌘R)")
          .accessibilityLabel("Refresh")
        }
        if panel.showsLogs {
          Button {
            panel.openLogs()
          } label: {
            Image(systemName: "text.alignleft")
          }
          .buttonStyle(CircleButtonStyle())
          .help("Logs")
          .accessibilityLabel("Logs")
        }
        Button {
          Task { await panel.openSettings() }
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(CircleButtonStyle())
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
      }
      .frame(height: LibraryControls.header)
      if library.isKindlePluggedIn {
        SideSwitch(panel: panel)
          .frame(height: LibraryControls.sideSwitch)
          .padding(.top, LibraryControls.sideSwitchGap)
      }
      DestinationChips(panel: panel)
        .frame(height: LibraryControls.chips)
        .padding(.top, LibraryControls.chipsGap(withKindle: library.isKindlePluggedIn))
      if isKindleSide {
        SearchField(
          text: Bindable(panel.kindle).query, prompt: "Search this Kindle",
          focusRequests: panel.searchFocusRequests
        )
        .frame(height: LibraryControls.search)
        .padding(.top, LibraryControls.searchGap)
        KindleFilterBar(library: library, kindle: panel.kindle)
          .padding(.top, LibraryControls.filterGap)
      } else {
        SearchField(
          text: Bindable(library).query, prompt: "Search title or author",
          focusRequests: panel.searchFocusRequests
        )
        .frame(height: LibraryControls.search)
        .padding(.top, LibraryControls.searchGap)
        FilterBar(library: library).padding(.top, LibraryControls.filterGap)
      }
      if let notice = panel.notice {
        NoticeView(
          toast: Toast(tone: .failure, notice), onFix: { Task { await panel.performNoticeFix() } },
          onDismiss: { panel.dismissNotice() }
        )
        .padding(.top, 10)
      }
      ZStack(alignment: .top) {
        if isKindleSide {
          KindleContent(panel: panel).transition(books(.kindle))
        } else {
          LibraryContent(panel: panel).transition(books(.library))
        }
      }
      .padding(.top, BooksArea.controlsGap)
    }
    .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: panel.side)
    .padding(BooksArea.screenPadding)
    .overlay(alignment: .bottom) {
      if panel.showsSendBar {
        SendBar(panel: panel)
          .padding(14)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottom) {
      // Scoped to the toast, so the books a hide takes out of the list don't move with it.
      ZStack {
        if let hidden = panel.shownHideToast {
          UndoToast(title: hidden.title, ends: panel.hideToastEnds) {
            Task { await panel.undoHide() }
          }
          .padding(14)
          // Above the send bar, while a selection the hide left keeps it up.
          .padding(.bottom, panel.sendBarRoom)
          .id(hidden)
          .transition(toastTransition)
        }
      }
      .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: panel.shownHideToast)
    }
    .animation(reduceMotion ? nil : Theme.press, value: panel.showsSendBar)
    .overlay(alignment: .bottom) {
      if let held = panel.undoToast {
        UndoToast(title: "Deleted \"\(held.book.title)\"", ends: panel.removal?.toastEnds) {
          Task { await panel.undoKindleDelete() }
        }
        .padding(14)
        .id(held.id)
        .transition(toastTransition)
      }
    }
    .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: panel.undoToast?.id)
  }

  private var toastTransition: AnyTransition {
    reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
  }

  private func books(_ side: LibrarySide) -> AnyTransition {
    ScreenMotion.books(side, reduceMotion: reduceMotion).transition
  }

  private var subtitle: String {
    if panel.side == .kindle { return panel.kindle.subtitle }
    return switch panel.library.state {
    case .loading: "Reading your Books library…"
    case .loaded: panel.library.summary
    case .failed: "Library unavailable"
    }
  }
}

struct DestinationChips: View {
  let panel: PanelModel

  /// One line however many Kindles are plugged in; it scrolls sideways when they don't fit.
  var body: some View {
    let library = panel.library
    ScrollView(.horizontal) {
      chips(library)
    }
    .scrollIndicators(.never)
  }

  /// The Kindle side shows only the Kindle it reads: Kindle email doesn't apply there.
  private func chips(_ library: LibraryViewModel) -> some View {
    let isKindleSide = panel.side == .kindle
    let destinations =
      isKindleSide
      ? library.destinations.filter { $0.volume == library.kindleVolume } : library.destinations
    return HStack(spacing: 6) {
      if !library.isKindlePluggedIn {
        Chip(
          title: "No Kindle plugged in", symbol: DestinationKind.usb.symbol, isActive: false
        )
        .help("Plug in a Kindle with its USB cable to copy books to it")
      }
      ForEach(destinations, id: \.self) { destination in
        if case .usb(let volume) = destination {
          KindleChip(panel: panel, destination: destination, volume: volume)
        } else {
          Button {
            Task { await library.activate(destination) }
          } label: {
            Chip(
              title: destination.label, symbol: destination.symbol,
              tint: Theme.tint(for: destination.kind),
              isActive: destination == library.activeDestination)
          }
          .buttonStyle(.plain)
          .help(destination.chipHelp)
          .accessibilityLabel(destination.spokenName)
        }
      }
      if !library.hasKindleEmail, !isKindleSide {
        Button {
          panel.showSetup(at: .kindleEmail)
        } label: {
          Chip(title: "Set up Kindle email", symbol: "plus", isActive: false)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// A plugged-in Kindle's chip. Eject slides in at its right edge while the pointer is on it, and
/// VoiceOver finds it as an action.
private struct KindleChip: View {
  let panel: PanelModel
  let destination: Destination
  let volume: KindleVolume
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var focus: Focus?

  private enum Focus {
    case chip, eject
  }

  var body: some View {
    let isActive = destination == panel.library.activeDestination
    let showsEject = panel.showsEject(in: volume)
    let tint = Theme.tint(for: destination.kind)
    HStack(spacing: 0) {
      Button {
        Task { await panel.library.activate(destination) }
      } label: {
        ChipLabel(
          title: destination.label, symbol: destination.symbol, tint: tint, isActive: isActive,
          trailingPadding: showsEject ? 6 : 10
        )
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .focused($focus, equals: .chip)
      .help(destination.chipHelp)
      .accessibilityLabel(destination.spokenName)
      .accessibilityAddTraits(isActive ? .isSelected : [])
      .accessibilityActions {
        if let name = panel.ejectActionName(for: volume) {
          Button(name) { Task { await panel.eject(volume) } }
        }
      }
      if showsEject {
        EjectButton(panel: panel, volume: volume)
          .focused($focus, equals: .eject)
          .padding(.trailing, 3)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .clipShape(Capsule())
    .chipShape(tint: tint, isActive: isActive)
    .onChange(of: focus != nil) { _, hasFocus in
      if hasFocus {
        panel.focusedChip = volume
      } else if panel.focusedChip == volume {
        panel.focusedChip = nil
      }
    }
    .onHover { isHovering in
      if isHovering {
        panel.hoveredChip = volume
      } else if panel.hoveredChip == volume {
        panel.hoveredChip = nil
      }
    }
    .onDisappear {
      if panel.hoveredChip == volume { panel.hoveredChip = nil }
      if panel.focusedChip == volume { panel.focusedChip = nil }
    }
    .animation(reduceMotion ? nil : Theme.press, value: showsEject)
  }
}

/// Ejects a plugged-in Kindle, except while a book is being copied to it.
private struct EjectButton: View {
  let panel: PanelModel
  let volume: KindleVolume

  var body: some View {
    let canEject = panel.canEject(volume)
    Button {
      Task { await panel.eject(volume) }
    } label: {
      Group {
        if panel.ejecting == volume {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "eject.fill").font(.system(size: 8, weight: .bold))
        }
      }
      .frame(width: 20, height: 20)
      .background(Theme.glass, in: Circle())
      .overlay(Circle().strokeBorder(Theme.line))
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color(hex: 0xc9d3ea))
    .disabled(!canEject)
    .opacity(canEject || panel.ejecting == volume ? 1 : 0.4)
    .help(help(canEject: canEject))
    .accessibilityLabel("Eject \(volume.name)")
  }

  private func help(canEject: Bool) -> String {
    if canEject { return "Eject \(volume.name)" }
    if let ejecting = panel.ejecting { return "Ejecting \(ejecting.name)…" }
    return "Wait until the copy is done to eject it"
  }
}

/// A destination, or a hint where one could be. `tint` is the destination's colour: its icon
/// carries it, and the active chip glows with it.
struct Chip: View {
  let title: String
  let symbol: String
  var tint: Color?
  let isActive: Bool

  var body: some View {
    ChipLabel(title: title, symbol: symbol, tint: tint, isActive: isActive)
      .chipShape(tint: tint, isActive: isActive)
      .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

private struct ChipLabel: View {
  let title: String
  let symbol: String
  var tint: Color?
  let isActive: Bool
  var trailingPadding: CGFloat = 10

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint.map { isActive ? $0 : $0.opacity(0.75) } ?? Theme.faint)
        .accessibilityHidden(true)
      Text(title).lineLimit(1)
    }
    .fixedSize()
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(isActive ? Theme.text : Color.white.opacity(0.7))
    .padding(.leading, 10)
    .padding(.trailing, trailingPadding)
    .padding(.vertical, 6)
  }
}

extension View {
  fileprivate func chipShape(tint: Color?, isActive: Bool) -> some View {
    let shape = Capsule()
    return
      background(isActive ? (tint ?? Theme.accent).opacity(0.18) : Theme.glass, in: shape)
      .overlay(shape.strokeBorder(isActive ? (tint ?? Theme.accent).opacity(0.85) : Theme.line))
  }
}

struct SearchField: View {
  @Binding var text: String
  let prompt: String
  let focusRequests: Int
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      TextField("Search", text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .focused($isFocused)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.faint)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .glass(cornerRadius: 12)
    .onChange(of: focusRequests) { isFocused = true }
  }
}

package struct FilterBar: View {
  @Bindable var library: LibraryViewModel

  package init(library: LibraryViewModel) {
    self.library = library
  }

  package var body: some View {
    FilterRow(library: library, title: "Library", selected: library.filter) {
      ForEach(library.filters, id: \.self) { filter in
        Button(filter.title) { library.filter = filter }
          .buttonStyle(FilterPillStyle(isOn: library.filter == filter))
          .accessibilityAddTraits(library.filter == filter ? .isSelected : [])
          .id(filter)
      }
    } format: {
      FormatMenu(library: library)
    }
  }
}

/// The Kindle side's scopes and formats, with the library's sort and layout.
struct KindleFilterBar: View {
  let library: LibraryViewModel
  @Bindable var kindle: KindleViewModel

  var body: some View {
    FilterRow(
      library: library, title: "On this Kindle", selected: kindle.scope,
      sortHelp: "Sort this Kindle"
    ) {
      ForEach(KindleScope.allCases, id: \.self) { scope in
        Button(scope.title) { kindle.scope = scope }
          .buttonStyle(FilterPillStyle(isOn: kindle.scope == scope))
          .accessibilityAddTraits(kindle.scope == scope ? .isSelected : [])
          .id(scope)
      }
    } format: {
      KindleFormatMenu(kindle: kindle)
    }
  }
}

/// The scope pills on a row of their own, with the list's title above the menus and layouts. The
/// pills scroll if they ever don't fit: the chosen one is kept in view and the strip fades where
/// it is cut off.
private struct FilterRow<Scopes: View, Format: View, Selection: Hashable>: View {
  private static var fadeWidth: CGFloat { 14 }

  let library: LibraryViewModel
  let title: String
  let selected: Selection
  var sortHelp = "Sort the library"
  @ViewBuilder let scopes: Scopes
  @ViewBuilder let format: Format
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: LibraryControls.filterSpacing) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 5) { scopes }.padding(.trailing, Self.fadeWidth)
        }
        .scrollIndicators(.never)
        .mask(alignment: .trailing) {
          HStack(spacing: 0) {
            Rectangle()
            LinearGradient(
              colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
            )
            .frame(width: Self.fadeWidth)
          }
        }
        .onAppear { proxy.scrollTo(selected, anchor: .center) }
        .onChange(of: selected) {
          withAnimation(reduceMotion ? nil : Theme.press) {
            proxy.scrollTo(selected, anchor: .center)
          }
        }
      }
      .frame(height: LibraryControls.scopes)
      HStack(spacing: 5) {
        SectionLabel(title)
        format
        SortMenu(library: library, help: sortHelp)
        LayoutSwitcher(library: library)
      }
      .frame(height: LibraryControls.menus)
    }
  }
}

/// All formats, EPUB or PDF.
struct FormatMenu: View {
  @Bindable var library: LibraryViewModel

  var body: some View {
    Menu {
      choice(nil, "All formats")
      ForEach(BookFormat.allCases, id: \.self) { choice($0, $0.rawValue.uppercased()) }
    } label: {
      Text(label).toolbarPill()
    }
    .pillMenu()
    .help("Show one format")
    .accessibilityLabel("Format")
    .accessibilityValue(label)
  }

  private var label: String { library.format.map { $0.rawValue.uppercased() } ?? "All formats" }

  @ViewBuilder
  private func choice(_ format: BookFormat?, _ title: String) -> some View {
    Button {
      library.format = format
    } label: {
      if format == library.format {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }
}

/// All the formats on the Kindle.
struct KindleFormatMenu: View {
  @Bindable var kindle: KindleViewModel

  var body: some View {
    Menu {
      choice(nil, "All formats")
      ForEach(kindle.formats, id: \.self) { choice($0, $0.uppercased()) }
    } label: {
      Text(label).toolbarPill()
    }
    .pillMenu()
    .help("Show one format")
    .accessibilityLabel("Format")
    .accessibilityValue(label)
  }

  private var label: String { kindle.format?.uppercased() ?? "All formats" }

  @ViewBuilder
  private func choice(_ format: String?, _ title: String) -> some View {
    Button {
      kindle.format = format
    } label: {
      if format == kindle.format {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }
}

/// Recently added, Title or Author; the A–Z bar shows for the last two.
struct SortMenu: View {
  let library: LibraryViewModel
  var help = "Sort the library"

  var body: some View {
    Menu {
      ForEach(LibrarySort.allCases, id: \.self) { sort in
        Button {
          Task { await library.setSort(sort) }
        } label: {
          if sort == library.sort {
            Label(sort.title, systemImage: "checkmark")
          } else {
            Text(sort.title)
          }
        }
      }
    } label: {
      HStack(spacing: 3) {
        Image(systemName: "arrow.up.arrow.down").font(.system(size: 8.5, weight: .bold))
        Text(library.sort == .recent ? "Recent" : library.sort.title)
      }
      .toolbarPill()
    }
    .pillMenu()
    .help(help)
    .accessibilityLabel("Sort")
    .accessibilityValue(library.sort.title)
  }
}

extension View {
  /// The glass pill a filter bar menu shows as its label.
  fileprivate func toolbarPill() -> some View {
    font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .glass(cornerRadius: 9)
      .contentShape(Rectangle())
  }

  fileprivate func pillMenu() -> some View {
    menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
  }
}

struct FilterPillStyle: ButtonStyle {
  let isOn: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(isOn ? Theme.text : Theme.muted)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(isOn ? Theme.glassHigh : .clear, in: Capsule())
      .contentShape(Capsule())
  }
}

struct LayoutSwitcher: View {
  let library: LibraryViewModel

  private let choices: [(LibraryLayout, String, String)] = [
    (.grid, "square.grid.3x2", "Grid (⌘1)"), (.list, "list.bullet", "List (⌘2)"),
    (.shelf, "books.vertical", "Shelf (⌘3)"),
  ]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(choices, id: \.0) { layout, symbol, help in
        let isOn = library.layout == layout
        Button {
          Task { await library.setLayout(layout) }
        } label: {
          Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isOn ? Theme.text : Theme.muted)
            .frame(width: 24, height: 20)
            .background(
              isOn ? Color.white.opacity(0.14) : .clear,
              in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(isOn ? 0.4 : 0), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
    .padding(2)
    .glass(cornerRadius: 9)
  }
}

/// Library | On Kindle, while a Kindle is plugged in.
struct SideSwitch: View {
  let panel: PanelModel

  private let sides: [LibrarySide] = [.library, .kindle]

  var body: some View {
    SegmentedSwitch(
      label: "Books", options: sides, selection: panel.side, fillsWidth: true,
      title: panel.switchTitle, choose: panel.showSide)
  }
}

struct LibraryContent: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    Group {
      switch library.state {
      case .loading:
        SkeletonBooks(layout: library.layout).transition(.opacity)
      case .failed(let problem):
        ProblemCard(problem: problem) { action in Task { await panel.perform(action) } }
          .frame(maxHeight: .infinity, alignment: .top)
      case .loaded:
        loaded(library).transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : Theme.press, value: library.state == .loading)
  }

  @ViewBuilder
  private func loaded(_ library: LibraryViewModel) -> some View {
    let items = library.items
    if items.isEmpty {
      EmptyLibraryView(library: library)
    } else {
      BooksScroll(
        jump: library.letterJump, style: library.jumpBar,
        scrollToTopRequests: library.scrollToTopRequests, bottomRoom: panel.sendBarRoom,
        floatingSide: panel.floatingRailSide,
        pinned: library.layout == .shelf
          ? BookShelfStrip(panel: panel, recent: library.recentItems) : nil
      ) {
        switch library.layout {
        case .grid:
          BookGrid(panel: panel, items: items)
        case .list, .shelf:
          BookList(panel: panel, items: items)
        }
      }
    }
  }
}

/// The send bar over the bottom of the books.
struct SendBar: View {
  let panel: PanelModel

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    SendBarContent(panel: panel)
      .background(Theme.floating, in: shape)
      .overlay(shape.strokeBorder(Color.white.opacity(0.1)))
      .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
  }
}

/// "Send" to the active destination, whose menu switches it, with how many books are selected.
struct SendBarContent: View {
  let panel: PanelModel

  var body: some View {
    let library = panel.library
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("\(library.selection.count) selected")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.75))
        Text(panel.sendBarHint)
          .font(.system(size: 9.5))
          .foregroundStyle(Theme.faint)
      }
      .lineLimit(1)
      Spacer(minLength: 8)
      HStack(spacing: 0) {
        // The whole label sends; only the arrow opens the menu.
        Button {
          Task { await panel.sendSelection() }
        } label: {
          HStack(spacing: 4) {
            Text("Send to")
            if let destination = library.activeDestination {
              Image(systemName: destination.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .opacity(0.85)
                .accessibilityHidden(true)
              Text(destination.label).opacity(0.85)
            } else {
              Text("Kindle").opacity(0.85)
            }
          }
          .padding(.leading, 14)
          .padding(.trailing, 8)
          .frame(minHeight: 34)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressedOpacityStyle())
        .fixedSize()
        .accessibilityLabel("Send to \(library.activeDestination?.spokenName ?? "Kindle")")
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 16)
        Menu {
          ForEach(library.destinations, id: \.self) { destination in
            Button {
              Task { await library.activate(destination) }
            } label: {
              Label(destination.label, systemImage: destination.symbol)
            }
          }
        } label: {
          Text("▾").opacity(0.75)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        // Drawn by SwiftUI, unlike `.borderlessButton`, so the padding takes clicks too.
        .menuStyle(.button)
        .buttonStyle(PressedOpacityStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose where Send goes")
        .accessibilityLabel("Choose where Send goes")
        .accessibilityValue(library.activeDestination?.spokenName ?? "Kindle")
      }
      .font(.system(size: 12.5, weight: .semibold))
      .foregroundStyle(.white)
      .background(
        Theme.action(for: library.activeKind),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .opacity(library.canSend ? 1 : 0.4)
      .disabled(!library.canSend)
    }
    .padding(.leading, 12)
    .padding(8)
  }
}

/// The Undo of a delete from the Kindle or a hide, over the bottom of the books, with a bar for the
/// time left. It says nothing to the menu bar icon.
struct UndoToast: View {
  let title: String
  /// Given, not read from the model, so a fading toast's bar doesn't fill up again.
  let ends: Date?
  let undo: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    HStack(spacing: 10) {
      Image(systemName: "checkmark")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Theme.live)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 4)
      Button("Undo", action: undo)
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Theme.link)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Theme.live.opacity(0.1), in: shape)
    .background(Theme.floating, in: shape)
    .overlay(alignment: .bottom) {
      TimeLeftBar(ends: ends, isMoving: !reduceMotion)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }
    .overlay(shape.strokeBorder(Theme.live.opacity(0.3)))
    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
    .help("Undo (⌘Z)")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityAction(named: "Undo", undo)
  }
}

/// The share of the Undo window left until `ends`; with Reduce Motion it stays full.
private struct TimeLeftBar: View {
  let ends: Date?
  let isMoving: Bool

  var body: some View {
    TimelineView(.animation(paused: !isMoving)) { context in
      Capsule()
        .fill(Theme.link.opacity(0.8))
        .frame(height: 2)
        .scaleEffect(x: isMoving ? left(at: context.date) : 1, anchor: .leading)
    }
    .accessibilityHidden(true)
  }

  private func left(at date: Date) -> CGFloat {
    guard let ends else { return 1 }
    let share = ends.timeIntervalSince(date) / (KindleRemovals.undoWindow / .seconds(1))
    return CGFloat(min(max(share, 0), 1))
  }
}

/// Dims a plain button while it's held down.
struct PressedOpacityStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
  }
}

struct ProblemCard: View {
  let problem: Problem
  let perform: (FixAction) -> Void

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Theme.warm)
        .accessibilityHidden(true)
      Text(problem.title).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
      if let message = problem.message {
        Text(message)
          .font(.system(size: 11.5))
          .foregroundStyle(Theme.muted)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let fix = problem.fix {
        Button(fix.label) { perform(fix.action) }
          .buttonStyle(PrimaryButtonStyle())
          .padding(.top, 4)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 22)
    .frame(maxWidth: .infinity)
    .glass(cornerRadius: 18)
  }
}

struct EmptyLibraryView: View {
  let library: LibraryViewModel

  var body: some View {
    if library.isEverythingHidden {
      EmptyPlaceholder(
        symbol: "eye.slash", title: "All your books are hidden",
        message: "Bring them back from Hidden.")
    } else if library.books.isEmpty {
      EmptyPlaceholder(
        symbol: "books.vertical", title: "Your Books library is empty",
        message: "Add EPUB or PDF files to Books, and they show up here.")
    } else {
      EmptyPlaceholder(
        symbol: "magnifyingglass", title: "No books match",
        message: "Try another search or filter.")
    }
  }
}

/// A centred icon, a title and a line of explanation, for a list with nothing to show.
struct EmptyPlaceholder: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 22))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      Text(title).font(.system(size: 13, weight: .semibold))
      Text(message)
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
