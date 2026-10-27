import SendleDomain
import SwiftUI

/// What Sendle did underneath: search, area pills, level bubbles and the lines, on a sheet over
/// the screen the logs were opened from.
struct LogsScreen: View {
  let panel: PanelModel

  var body: some View {
    let logs = panel.logs
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Button {
          panel.closeLogs()
        } label: {
          Image(systemName: "chevron.left")
        }
        .buttonStyle(CircleButtonStyle())
        .help("Back (Esc)")
        .accessibilityLabel("Back")
        VStack(alignment: .leading, spacing: 1) {
          Text("Logs").font(.system(size: 15, weight: .semibold))
          Text("Kept in memory until Sendle quits")
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
        }
        Spacer(minLength: 8)
        Button("Copy") { panel.copyLogs() }
          .buttonStyle(SecondaryButtonStyle())
          .help("Copy the lines shown")
        Button("Clear") { logs.clear() }
          .buttonStyle(SecondaryButtonStyle())
      }
      LogSearchField(logs: logs).padding(.top, 12)
      LogFilters(logs: logs).padding(.top, 9)
      LogList(logs: logs).padding(.top, 10)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CardBackground())
  }
}

private struct LogSearchField: View {
  @Bindable var logs: LogsViewModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      TextField(
        "Search logs", text: $logs.query, prompt: Text("Search logs").foregroundStyle(Theme.faint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .glass(cornerRadius: 12)
  }
}

private struct LogFilters: View {
  @Bindable var logs: LogsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 5) {
        ForEach(LogAreaFilter.allCases, id: \.self) { area in
          Button(area.title) { logs.area = area }
            .buttonStyle(FilterPillStyle(isOn: logs.area == area))
            .accessibilityAddTraits(logs.area == area ? .isSelected : [])
        }
      }
      HStack(spacing: 5) {
        ForEach(LogLevel.allCases, id: \.self) { level in
          Button {
            logs.toggle(level)
          } label: {
            LevelBubble(level: level, size: 9)
          }
          .buttonStyle(.plain)
          .opacity(logs.isShowing(level) ? 1 : 0.35)
          .help(logs.isShowing(level) ? "Hide \(level.label) lines" : "Show \(level.label) lines")
          .accessibilityLabel(level.label)
          .accessibilityAddTraits(logs.isShowing(level) ? .isSelected : [])
        }
        Spacer(minLength: 0)
        Text("Click a level to hide it")
          .font(.system(size: 9.5))
          .foregroundStyle(Theme.faint)
      }
    }
  }
}

struct LevelBubble: View {
  let level: LogLevel
  var size: CGFloat = 7.5

  var body: some View {
    let color = level.color
    Text(level.label)
      .font(.system(size: size, weight: .heavy))
      .kerning(0.3)
      .foregroundStyle(color)
      .padding(.horizontal, size * 0.7)
      .padding(.vertical, size * 0.25)
      .background(color.opacity(0.18), in: Capsule())
      .overlay(Capsule().strokeBorder(color.opacity(0.4)))
  }
}

private struct LogList: View {
  let logs: LogsViewModel

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(logs.visible) { entry in
            LogRow(logs: logs, entry: entry).id(entry.id)
          }
          Color.clear.frame(height: 1)
            .onAppear { logs.isAtBottom = true }
            .onDisappear { logs.isAtBottom = false }
            .id(Self.bottom)
        }
        .padding(.vertical, 6)
      }
      .scrollIndicators(.automatic)
      .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
      .overlay {
        if logs.visible.isEmpty {
          Text(logs.query.isEmpty ? "Nothing logged yet." : "No lines match.")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.faint)
        }
      }
      .onChange(of: logs.visible.last?.id) {
        if logs.isAtBottom { proxy.scrollTo(Self.bottom, anchor: .bottom) }
      }
      .onChange(of: logs.revealRequests) {
        if let target = logs.scrollTarget { proxy.scrollTo(target, anchor: .top) }
      }
      // The newest lines are there as the logs come up, before any scroll could run.
      .defaultScrollAnchor(logs.scrollTarget == nil ? .bottom : .top)
      .onAppear {
        if let target = logs.scrollTarget { proxy.scrollTo(target, anchor: .top) }
      }
    }
  }

  private static let bottom = -1
}

private struct LogRow: View {
  let logs: LogsViewModel
  let entry: LogEntry

  var body: some View {
    if entry.heading != nil {
      Text(marked(entry.message))
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    } else {
      line
    }
  }

  private func marked(_ text: String) -> AttributedString {
    var marked = AttributedString(text)
    for range in logs.highlights(in: text) {
      if let span = Range(range, in: marked) {
        marked[span].backgroundColor = Theme.warm.opacity(0.35)
      }
    }
    return marked
  }

  private var line: some View {
    let extra = LogsViewModel.extraLines(in: entry)
    let isOpen = logs.isExpanded(entry)
    let firstLine = entry.message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    return HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(logs.time(of: entry))
        .foregroundStyle(Theme.faint)
      Text(entry.area.tag)
        .font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(entry.area.color)
        .frame(width: 40, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          LevelBubble(level: entry.level)
          Text(marked(firstLine)).foregroundStyle(entry.level.textColor)
          if extra > 0 {
            Button {
              logs.toggleExpanded(entry)
            } label: {
              Text(isOpen ? "▾ \(extra + 1) lines" : "▸ \(extra) more lines")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.link)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.accent.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
          }
        }
        if isOpen {
          Text(marked(entry.message))
            .foregroundStyle(Color.white.opacity(0.75))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08)))
        }
      }
    }
    .font(.system(size: 10.5, design: .monospaced))
    .padding(.horizontal, 10)
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(entry.level == .error ? Theme.danger.opacity(0.1) : .clear)
    .accessibilityElement(children: .combine)
  }
}

extension LogLevel {
  var color: Color {
    switch self {
    case .debug: Color(hex: 0xcbd5e1)
    case .info: Theme.link
    case .warning: Theme.warm
    case .error: Color(hex: 0xff8a8a)
    }
  }

  var textColor: Color {
    switch self {
    case .debug: Color.white.opacity(0.6)
    case .info: Color.white.opacity(0.85)
    case .warning: Theme.warm
    case .error: Color(hex: 0xff8a8a)
    }
  }
}

extension LogArea {
  var color: Color {
    switch self {
    case .mail: Color(hex: 0x7fb2ff)
    case .boko: Color(hex: 0xfbbf24)
    case .usb: Theme.live
    case .library, .epub, .lookup: Color(hex: 0xc4b5fd)
    case .app: Theme.muted
    }
  }
}
