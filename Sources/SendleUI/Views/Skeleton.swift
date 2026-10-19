import SendleDomain
import SwiftUI

/// A placeholder block: a soft band sweeps over it once per 1.4 s, and with Reduce Motion it stays
/// still.
struct ShimmerFill: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Theme.glass.overlay {
      if !reduceMotion {
        TimelineView(.animation) { context in
          GeometryReader { geometry in
            let cycle = context.date.timeIntervalSinceReferenceDate / 1.4
            let phase = cycle - cycle.rounded(.down)
            LinearGradient(
              colors: [.clear, Color.white.opacity(0.06), .clear], startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: (phase * 1.6 - 0.6) * geometry.size.width)
          }
        }
      }
    }
    .clipped()
  }
}

/// A cover that hasn't been read yet, in the covers' shape.
struct SkeletonCover: View {
  var body: some View {
    ShimmerFill().clipShape(CoverFace.shape)
  }
}

private struct SkeletonLine: View {
  let width: CGFloat
  var height: CGFloat = 7

  var body: some View {
    ShimmerFill()
      .frame(width: width, height: height)
      .clipShape(Capsule())
  }
}

/// What the library and the Kindle show while their books are read: the layout in placeholders.
struct SkeletonBooks: View {
  let layout: LibraryLayout

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch layout {
      case .grid:
        label.padding(.bottom, 10)
        grid
      case .list:
        label.padding(.bottom, 8)
        rows(7)
      case .shelf:
        label
        covers
        label.padding(.top, 6).padding(.bottom, 8)
        rows(5)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading books")
  }

  private var label: some View {
    SkeletonLine(width: 70, height: 6).padding(.horizontal, 2)
  }

  private var grid: some View {
    LazyVGrid(columns: bookGridColumns, alignment: .leading, spacing: 12) {
      ForEach(0..<9, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 0) {
          SkeletonCover().aspectRatio(2 / 3, contentMode: .fit)
          SkeletonLine(width: 64, height: 8).padding(.top, 8).padding(.bottom, 3)
          SkeletonLine(width: 42, height: 6).padding(.vertical, 2)
        }
      }
    }
    .padding(.horizontal, 4)
  }

  /// Six covers wider than the panel, as the shelf's row scrolls past its edge.
  private var covers: some View {
    Color.clear
      .frame(height: 93 + 16)
      .overlay(alignment: .leading) {
        HStack(spacing: 10) {
          ForEach(0..<6, id: \.self) { _ in SkeletonCover().frame(width: 62, height: 93) }
        }
        .padding(.horizontal, 6)
      }
      .clipped()
  }

  private func rows(_ count: Int) -> some View {
    VStack(spacing: 2) {
      ForEach(0..<count, id: \.self) { _ in
        HStack(spacing: 10) {
          SkeletonCover().frame(width: 34, height: 50)
          VStack(alignment: .leading, spacing: 5) {
            SkeletonLine(width: 130, height: 9)
            SkeletonLine(width: 86, height: 7)
            SkeletonLine(width: 56, height: 6)
          }
          Spacer(minLength: 6)
        }
        .padding(7)
      }
    }
  }
}
