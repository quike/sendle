import SendleDomain
import SwiftUI

struct LibraryScreen: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    VStack(alignment: .leading, spacing: 0) {
      PanelHeader(title: "Sendle", subtitle: subtitle) {
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
      DestinationChips(panel: panel).padding(.top, 12)
      SearchField(library: library, focusRequests: panel.searchFocusRequests).padding(.top, 10)
      FilterBar(library: library).padding(.top, 9)
      if let notice = panel.notice {
        NoticeView(
          toast: Toast(tone: .failure, notice), onFix: { Task { await panel.performNoticeFix() } },
          onDismiss: { panel.dismissNotice() }
        )
        .padding(.top, 10)
      }
      LibraryContent(panel: panel).padding(.top, 10)
    }
    .padding(14)
    .overlay(alignment: .bottom) {
      if !library.selection.isEmpty {
        SendBar(panel: panel)
          .padding(14)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : Theme.press, value: library.selection.isEmpty)
  }

  private var subtitle: String {
    switch panel.library.state {
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

  private func chips(_ library: LibraryViewModel) -> some View {
    HStack(spacing: 6) {
      if !library.isKindlePluggedIn {
        Chip(
          title: "No Kindle plugged in", symbol: DestinationKind.usb.symbol, isActive: false
        )
        .help("Plug in a Kindle with its USB cable to copy books to it")
      }
      ForEach(library.destinations, id: \.self) { destination in
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
        if case .usb(let volume) = destination {
          EjectButton(panel: panel, volume: volume)
        }
      }
      if !library.hasKindleEmail {
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

/// Ejects a plugged-in Kindle, except while a book is being copied to it.
struct EjectButton: View {
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
          Image(systemName: "eject.fill").font(.system(size: 9, weight: .bold))
        }
      }
      .frame(width: 26, height: 26)
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
    let shape = Capsule()
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
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(isActive ? (tint ?? Theme.accent).opacity(0.18) : Theme.glass, in: shape)
    .overlay(shape.strokeBorder(isActive ? (tint ?? Theme.accent).opacity(0.85) : Theme.line))
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

struct SearchField: View {
  @Bindable var library: LibraryViewModel
  let focusRequests: Int
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      TextField(
        "Search", text: $library.query,
        prompt: Text("Search title or author").foregroundStyle(Theme.faint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
      .focused($isFocused)
      if !library.query.isEmpty {
        Button {
          library.query = ""
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

struct FilterBar: View {
  @Bindable var library: LibraryViewModel

  var body: some View {
    HStack(spacing: 5) {
      ForEach(LibraryFilter.allCases, id: \.self) { filter in
        Button(filter.title) { library.filter = filter }
          .buttonStyle(FilterPillStyle(isOn: library.filter == filter))
          .accessibilityAddTraits(library.filter == filter ? .isSelected : [])
      }
      Spacer(minLength: 0)
      SortMenu(library: library)
      LayoutSwitcher(library: library)
    }
  }
}

/// Recently added, Title or Author; the A–Z bar shows for the last two.
struct SortMenu: View {
  let library: LibraryViewModel

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
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .glass(cornerRadius: 9)
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Sort the library")
    .accessibilityLabel("Sort")
    .accessibilityValue(library.sort.title)
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

struct LibraryContent: View {
  private static let top = "top"

  let panel: PanelModel

  var body: some View {
    let library = panel.library
    switch library.state {
    case .loading:
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let problem):
      ProblemCard(problem: problem) { action in Task { await panel.perform(action) } }
        .frame(maxHeight: .infinity, alignment: .top)
    case .loaded:
      let items = library.items
      if items.isEmpty {
        EmptyLibraryView(isFiltered: !library.books.isEmpty)
      } else {
        let fullRail = library.showsRail && library.jumpBar == .full
        GeometryReader { geometry in
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                switch library.layout {
                case .grid:
                  SectionLabel("Library").padding(.bottom, 7)
                  BookGrid(panel: panel, items: items)
                case .list:
                  SectionLabel("Library").padding(.bottom, 4)
                  BookList(panel: panel, items: items)
                case .shelf:
                  BookShelf(panel: panel, items: items, recent: library.recentItems)
                }
              }
              .id(Self.top)
              .padding(.trailing, fullRail ? AlphabetRail.width : 0)
              .padding(.bottom, library.selection.isEmpty ? 6 : 70)
            }
            .scrollIndicators(.never)
            .scrollPosition(id: Bindable(library).topBook, anchor: .top)
            .onChange(of: library.scrollToTopRequests) { proxy.scrollTo(Self.top, anchor: .top) }
          }
          .overlay(alignment: .trailing) {
            if library.showsRail {
              AlphabetRail(library: library).padding(.bottom, library.selection.isEmpty ? 0 : 64)
            }
          }
          // The compact A–Z bar shows while the pointer is near the right edge, the bar included.
          .onContinuousHover { phase in
            guard case .active(let point) = phase else { return library.isRailHovered = false }
            library.isRailHovered = point.x > geometry.size.width - 36
          }
        }
      }
    }
  }
}

/// "Send" to the active destination, whose menu switches it.
struct SendBar: View {
  let panel: PanelModel

  var body: some View {
    let library = panel.library
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("\(library.selection.count) selected")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.75))
        Text(library.canSend ? "\(library.sendHint) · Esc to clear" : library.sendHint)
          .font(.system(size: 9.5))
          .foregroundStyle(Theme.faint)
      }
      .lineLimit(1)
      Spacer(minLength: 8)
      HStack(spacing: 0) {
        // The whole label sends; only the arrow opens the menu.
        Button {
          panel.sendSelection()
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
    .background(Color(hex: 0x161b29).opacity(0.96), in: shape)
    .overlay(shape.strokeBorder(Color.white.opacity(0.1)))
    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
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
  let isFiltered: Bool

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: isFiltered ? "magnifyingglass" : "books.vertical")
        .font(.system(size: 22))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      Text(isFiltered ? "No books match" : "Your Books library is empty")
        .font(.system(size: 13, weight: .semibold))
      Text(
        isFiltered
          ? "Try another search or filter."
          : "Add EPUB or PDF files to Books, and they show up here."
      )
      .font(.system(size: 11.5))
      .foregroundStyle(Theme.muted)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
