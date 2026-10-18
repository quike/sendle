import SwiftUI

/// The books being sent: progress for each, the fixes Amazon needed, and what came of the run.
struct QueueScreen: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let queue = panel.queue
    VStack(alignment: .leading, spacing: 0) {
      PanelHeader(title: queue.title, subtitle: queue.subtitle) {
        if queue.isRunning {
          Button {
            queue.cancel()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(CircleButtonStyle())
          .help("Cancel the books not sent yet")
          .accessibilityLabel("Cancel sending")
        } else {
          Button("Done") { panel.finishQueue() }
            .buttonStyle(SecondaryButtonStyle())
            .help("Back to the library (Esc)")
        }
      }
      SectionLabel("Queue").padding(.top, 14).padding(.bottom, 4)
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(queue.rows) { row in QueueRowView(panel: panel, row: row) }
        }
      }
      .scrollIndicators(.never)
      if let summary = queue.summary {
        NoticeView(toast: summary, onFix: { Task { await panel.performQueueFix() } })
          .padding(.top, 10)
          .transition(.opacity)
      }
    }
    .padding(14)
    .animation(reduceMotion ? nil : Theme.press, value: queue.summary)
  }
}

private struct QueueRowView: View {
  let panel: PanelModel
  let row: QueueRow

  var body: some View {
    HStack(spacing: 10) {
      BookCover(panel: panel, book: row.book, size: .small)
        .frame(width: 34, height: 50)
      VStack(alignment: .leading, spacing: 2) {
        Text(row.book.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
        Text(row.detail).font(.system(size: 10)).foregroundStyle(row.tone.color).lineLimit(2)
        if let note = row.fixesNote {
          Text(note).font(.system(size: 10)).foregroundStyle(Theme.warm).lineLimit(2)
        }
        if panel.showsLogs, case .failed = row.status {
          ShowLogsLink { panel.openLogs(revealing: .book(row.book.id)) }
        }
      }
      Spacer(minLength: 6)
      QueueMark(status: row.status)
    }
    .padding(7)
    .accessibilityElement(children: .contain)
  }
}

/// Opens the logs at the story of a send that failed.
struct ShowLogsLink: View {
  let open: () -> Void

  var body: some View {
    Button("Show logs ›", action: open)
      .buttonStyle(.plain)
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(Color(hex: 0x9cc2ff))
      .padding(.top, 2)
  }
}

/// The round mark at the end of a row: a progress ring, a tick, a cross or "next".
private struct QueueMark: View {
  let status: QueueStatus

  var body: some View {
    Group {
      switch status {
      case .waiting:
        Text("next")
          .font(.system(size: 9))
          .foregroundStyle(Theme.faint)
          .frame(width: 30, height: 30)
          .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 2))
      case .preparing:
        ProgressView().controlSize(.small).frame(width: 30, height: 30)
      case .uploading(let fraction):
        ZStack {
          Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
          Circle().trim(from: 0, to: fraction).stroke(Theme.accent, lineWidth: 3)
            .rotationEffect(.degrees(-90))
          Text("\(Int((fraction * 100).rounded()))%")
            .font(.system(size: 8, weight: .bold).monospacedDigit())
            .foregroundStyle(Color(hex: 0x9cc2ff))
        }
        .frame(width: 30, height: 30)
      case .sent:
        Image(systemName: "checkmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Theme.live)
          .frame(width: 30, height: 30)
          .background(Theme.live.opacity(0.14), in: Circle())
      case .failed:
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(Theme.danger)
          .frame(width: 30, height: 30)
          .background(Theme.danger.opacity(0.14), in: Circle())
      case .cancelled:
        Color.clear.frame(width: 30, height: 30)
      }
    }
    .accessibilityHidden(true)
  }
}

extension QueueRow.Tone {
  var color: Color {
    switch self {
    case .waiting: Theme.faint
    case .active: Color(hex: 0x9cc2ff)
    case .sent: Theme.live
    case .failed: Theme.danger
    }
  }
}
