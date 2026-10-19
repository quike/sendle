import SendleDomain
import SwiftUI

/// What the Kindle side shows under its search: the books in the layout the library uses, with
/// nothing to select or send.
struct KindleContent: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let kindle = panel.kindle
    Group {
      switch kindle.state {
      case .failed(let problem):
        ProblemCard(problem: problem) { action in
          if action == .retry {
            Task { await kindle.refresh() }
          } else {
            Task { await panel.perform(action) }
          }
        }
        .frame(maxHeight: .infinity, alignment: .top)
      case .idle, .reading, .loaded:
        if let listing = kindle.listing {
          KindleBooks(panel: panel, isEmpty: listing.books.isEmpty).transition(.opacity)
        } else {
          SkeletonBooks(layout: panel.library.layout).transition(.opacity)
        }
      }
    }
    .animation(reduceMotion ? nil : Theme.press, value: kindle.listing != nil)
  }
}

private struct KindleBooks: View {
  let panel: PanelModel
  let isEmpty: Bool

  var body: some View {
    let kindle = panel.kindle
    let items = kindle.items
    if isEmpty {
      EmptyPlaceholder(
        symbol: "books.vertical", title: "This Kindle has no books",
        message: "Books you copy to it show up here.")
    } else if items.isEmpty {
      EmptyPlaceholder(
        symbol: "magnifyingglass", title: "No books match",
        message: "Try another search or filter.")
    } else {
      let style = panel.library.jumpBar
      // Letter headers come with the full A–Z bar, as in the library.
      let headers = style == .full ? kindle.letterJump.index : nil
      BooksScroll(
        jump: kindle.letterJump, style: style, scrollToTopRequests: kindle.scrollToTopRequests,
        floatingSide: panel.floatingRailSide
      ) {
        switch panel.library.layout {
        case .grid:
          KindleGrid(kindle: kindle, items: items, showsFormat: panel.showsFormatOnKindleCovers)
        case .list:
          KindleList(kindle: kindle, items: items, headers: headers)
        case .shelf:
          KindleShelf(kindle: kindle, items: items, recent: kindle.recentItems, headers: headers)
        }
      }
    }
  }
}

struct KindleGrid: View {
  let kindle: KindleViewModel
  let items: [KindleItemViewModel]
  let showsFormat: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    LazyVGrid(columns: bookGridColumns, alignment: .leading, spacing: 12) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 0) {
          KindleCover(kindle: kindle, item: item, size: .large, showsFormat: showsFormat)
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
        .kindleDescription(item)
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .scrollTargetLayout()
    .padding(.horizontal, BooksArea.gridInset)
  }
}

struct KindleList: View {
  let kindle: KindleViewModel
  let items: [KindleItemViewModel]
  let headers: AlphabetIndex<KindleBookID>?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    LazyVStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 2) {
          if let letter = headers?.header(before: item.id) {
            LetterHeader(letter: letter)
          }
          KindleRow(kindle: kindle, item: item)
        }
        .transition(Theme.entrance(index: index, reduceMotion: reduceMotion))
      }
    }
    .scrollTargetLayout()
  }
}

/// "Recently added" covers above the full list.
struct KindleShelf: View {
  let kindle: KindleViewModel
  let items: [KindleItemViewModel]
  let recent: [KindleItemViewModel]
  let headers: AlphabetIndex<KindleBookID>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionLabel("Recently added")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(recent) { item in
            KindleCover(kindle: kindle, item: item, size: .large, titleSize: 8)
              .frame(width: 62, height: 93)
              .kindleDescription(item)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
      }
      // Not past the trailing edge, which keeps the A–Z bar's gutter.
      .scrollOverflow([.vertical, .leading])
      .scrollIndicators(.never)
      SectionLabel("All books").padding(.top, 6).padding(.bottom, 4)
      KindleList(kindle: kindle, items: items, headers: headers)
    }
  }
}

struct KindleRow: View {
  let kindle: KindleViewModel
  let item: KindleItemViewModel

  var body: some View {
    HStack(spacing: 10) {
      KindleCover(kindle: kindle, item: item, size: .small)
        .frame(width: 34, height: 50)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
        Text(item.byline).font(.system(size: 10.5)).foregroundStyle(Theme.muted).lineLimit(1)
        HStack(spacing: 5) {
          FormatBadge(text: item.badge)
          Text(item.detail).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .font(.system(size: 9.5))
        .padding(.top, 2)
      }
      Spacer(minLength: 6)
    }
    .padding(7)
    .kindleDescription(item)
  }
}

/// A Kindle book's cover from the device, or a title card where it has none.
struct KindleCover: View {
  let kindle: KindleViewModel
  let item: KindleItemViewModel
  let size: CoverSize
  var titleSize: CGFloat = 10
  var showsFormat = false

  var body: some View {
    let book = item.book
    let look = CoverLook.of(book.isProtected ? .protected : .ready)
    let slot = kindle.covers.slot(for: book, size: size)
    CoverFace(
      data: slot.data, isPending: slot.isPending, title: item.title,
      seed: BookID(rawValue: book.id.relativePath), titleSize: size == .large ? titleSize : nil,
      bottomInset: showsFormat ? 16 : 0
    )
    .saturation(look.saturation)
    .brightness(look.brightness)
    .overlay {
      if book.isProtected {
        Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(.white)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if showsFormat { FormatBadge(text: item.badge, onCover: true).padding(6) }
    }
    .shadow(color: .black.opacity(0.45), radius: 8, y: 6)
    .task(id: book) {
      guard let volume = kindle.volume else { return }
      await kindle.covers.load(book, on: volume, size: size)
    }
    .accessibilityHidden(true)
  }
}

extension View {
  /// Hover shows the details; VoiceOver reads one element per book.
  func kindleDescription(_ item: KindleItemViewModel) -> some View {
    contentShape(Rectangle())
      .help(item.help)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(item.title), \(item.byline)")
      .accessibilityValue(item.spoken)
  }
}
