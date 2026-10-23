import SendleDomain
import SwiftUI

/// A details sheet's cover beside the book's format and facts, aligned to its bottom.
struct DetailsFactsRow<Cover: View>: View {
  let facts: [String]
  @ViewBuilder let cover: Cover

  var body: some View {
    HStack(alignment: .bottom, spacing: 14) {
      cover
      VStack(alignment: .leading, spacing: 5) {
        if let format = facts.first {
          Text(format)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.glassHigh, in: RoundedRectangle(cornerRadius: 5))
        }
        ForEach(facts.dropFirst(), id: \.self) { fact in
          Text(fact).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
    }
  }
}

/// Clicking the cover, or dropping an image on it, replaces it; its ↺ puts the book's own back. A
/// PDF's, or a book's still in iCloud, stays as it is.
struct DetailsCover: View {
  let panel: PanelModel
  @Bindable var details: BookDetailsViewModel

  var body: some View {
    let book = details.coverBook
    Group {
      if details.canChangeCover {
        Button {
          Task { await panel.chooseCoverImage() }
        } label: {
          face(of: book)
        }
        .buttonStyle(.plain)
        .onHover { details.isCoverHovered = $0 }
        .help("Choose another cover, or drop an image here")
        .accessibilityLabel("Change cover")
      } else {
        face(of: book).accessibilityHidden(true)
      }
    }
    .overlay(alignment: .topTrailing) {
      if details.isCoverEdited {
        Button {
          details.revertCover()
        } label: {
          Image(systemName: "arrow.uturn.backward")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.link)
            .frame(width: 20, height: 20)
            .background(Theme.background.opacity(0.85), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(5)
        .help("Back to the book's own cover")
        .accessibilityLabel("Revert cover")
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first, details.canChangeCover else { return false }
      Task { await panel.dropCover(url) }
      return true
    } isTargeted: { isTargeted in
      details.isCoverHovered = isTargeted
    }
    .frame(width: 78, height: 117)
    .shadow(color: .black.opacity(0.6), radius: 7, y: 6)
    .task(id: book) { await panel.covers.load(book, size: .large) }
  }

  /// Darkened, with a swap icon, while the pointer or a dragged file is over it.
  private func face(of book: Book) -> some View {
    let slot = panel.covers.slot(for: book, size: .large)
    let preview = details.coverPreview
    return CoverFace(
      data: preview ?? slot.data, isPending: preview == nil && slot.isPending, title: book.title,
      seed: book.id, titleSize: 10
    )
    .overlay {
      if details.isCoverHovered, details.canChangeCover {
        ZStack {
          Theme.background.opacity(0.45)
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.16), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
        }
        .clipShape(CoverFace.shape)
      }
    }
    .frame(width: 78, height: 117)
    .contentShape(CoverFace.shape)
  }
}
