import SendleDomain
import SwiftUI

private struct ShimmerPhaseKey: EnvironmentKey {
  static let defaultValue: Double? = nil
}

extension EnvironmentValues {
  /// Where the band is in its sweep, 0 to 1. A skeleton sets it once for all its blocks.
  fileprivate var shimmerPhase: Double? {
    get { self[ShimmerPhaseKey.self] }
    set { self[ShimmerPhaseKey.self] = newValue }
  }
}

/// A placeholder block: a soft band sweeps over it once per 1.4 s, and with Reduce Motion it stays
/// still. Blocks outside a skeleton keep their own time, which is the same clock.
struct ShimmerFill: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.shimmerPhase) private var sharedPhase

  static func phase(at date: Date) -> Double {
    let cycle = date.timeIntervalSinceReferenceDate / 1.4
    return cycle - cycle.rounded(.down)
  }

  var body: some View {
    Theme.glass.overlay {
      if !reduceMotion {
        if let sharedPhase {
          band(sharedPhase)
        } else {
          TimelineView(.animation) { band(Self.phase(at: $0.date)) }
        }
      }
    }
    .clipped()
  }

  private func band(_ phase: Double) -> some View {
    GeometryReader { geometry in
      LinearGradient(
        colors: [.clear, Color.white.opacity(0.06), .clear], startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: geometry.size.width * 0.6)
      .offset(x: (phase * 1.6 - 0.6) * geometry.size.width)
    }
  }
}

/// A cover that hasn't been read yet, in the covers' shape.
struct SkeletonCover: View {
  var body: some View {
    ShimmerFill()
      .clipShape(CoverFace.shape)
      .overlay(alignment: .leading) { CoverSpine() }
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// One timeline sweeps every block, and stands still with Reduce Motion.
  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      // The clear base takes the space there is; the placeholders, taller than it, are cut off
      // and never push the screen's header out of the card.
      Color.clear
        .overlay(alignment: .top) { content }
        .clipped()
        .environment(\.shimmerPhase, ShimmerFill.phase(at: context.date))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading books")
    }
  }

  /// The loaded layouts' metrics, so the books replace it without a jump.
  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch layout {
      case .grid:
        grid
      case .list:
        rows(7)
      case .shelf:
        label
        covers
        label.padding(.top, 6).padding(.bottom, 4)
        rows(5)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// As tall as a section label's line.
  private var label: some View {
    SkeletonLine(width: 70, height: 6).padding(.vertical, 3).padding(.horizontal, 2)
  }

  private var grid: some View {
    LazyVGrid(columns: bookGridColumns, alignment: .leading, spacing: 12) {
      ForEach(0..<9, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 0) {
          SkeletonCover().aspectRatio(2 / 3, contentMode: .fit)
          SkeletonLine(width: 64, height: 8).padding(.top, 8).padding(.bottom, 3)
          SkeletonLine(width: 42, height: 6).padding(.vertical, 3)
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
