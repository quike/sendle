import SendleDomain
import SwiftUI

struct LibraryScreen: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let library = panel.library
    VStack(alignment: .leading, spacing: 0) {
      PanelHeader(title: "Sendle", subtitle: subtitle) {
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
          problem: notice, onFix: { Task { await panel.performNoticeFix() } },
          onDismiss: { panel.dismissNotice() }
        )
        .padding(.top, 10)
      }
      LibraryContent(panel: panel).padding(.top, 10)
    }
    .padding(14)
    .overlay(alignment: .bottom) {
      if !library.selection.isEmpty {
        SendBar(library: library)
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

  var body: some View {
    let library = panel.library
    HStack(spacing: 6) {
      ForEach(library.destinations, id: \.self) { destination in
        Button {
          Task { await library.activate(destination.kind) }
        } label: {
          Chip(
            title: destination.chipTitle,
            dot: destination.kind == .usb ? Theme.live : Theme.accent,
            isActive: destination == library.activeDestination)
        }
        .buttonStyle(.plain)
        .help("Quick-send goes here")
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

struct Chip: View {
  let title: String
  var dot: Color?
  var symbol: String?
  let isActive: Bool

  var body: some View {
    let shape = Capsule()
    HStack(spacing: 6) {
      if let dot { StatusDot(color: dot) }
      if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
      Text(title)
    }
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(isActive ? Theme.text : Color.white.opacity(0.7))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(isActive ? Theme.accent.opacity(0.16) : Theme.glass, in: shape)
    .overlay(shape.strokeBorder(isActive ? Theme.accent.opacity(0.6) : Theme.line))
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
      }
      Spacer(minLength: 0)
      LayoutSwitcher(library: library)
    }
  }
}

private struct FilterPillStyle: ButtonStyle {
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
      }
    }
    .padding(2)
    .glass(cornerRadius: 9)
  }
}

struct LibraryContent: View {
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
          .padding(.bottom, library.selection.isEmpty ? 6 : 70)
        }
        .scrollIndicators(.never)
      }
    }
  }
}

struct SendBar: View {
  let library: LibraryViewModel

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("\(library.selection.count) selected · Esc to clear")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.75))
        Text(library.sendHint).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
      }
      Spacer(minLength: 8)
      Button {
      } label: {
        HStack(spacing: 5) {
          Text("Send")
          Text("to \(library.activeDestination?.chipTitle ?? "Kindle")").opacity(0.75)
        }
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(!library.canSend)
    }
    .padding(.leading, 12)
    .padding(8)
    .background(Color(hex: 0x161b29).opacity(0.96), in: shape)
    .overlay(shape.strokeBorder(Color.white.opacity(0.1)))
    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
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
