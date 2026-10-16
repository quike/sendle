import SendleDomain

/// How a click changes the selection: ⌘ toggles one book, ⇧ adds a range.
package enum ClickKind: Sendable {
  case plain
  case toggle
  case range
}

package enum MoveDirection: Sendable {
  case up
  case down
  case left
  case right
}

/// The selected books. Only books that can go to the active destination are ever selected.
package struct Selection: Equatable, Sendable {
  package private(set) var ids: Set<BookID> = []
  /// Where ⇧-click ranges start.
  package private(set) var anchor: BookID?
  /// Where arrow keys start: the book clicked or reached last.
  package private(set) var lead: BookID?

  package init() {}

  package var isEmpty: Bool { ids.isEmpty }
  package var count: Int { ids.count }

  package func contains(_ id: BookID) -> Bool { ids.contains(id) }

  package mutating func click(_ id: BookID, _ kind: ClickKind, in items: [BookItemViewModel]) {
    guard items.contains(where: { $0.id == id && $0.canSend }) else { return }
    switch kind {
    case .plain:
      ids = [id]
      anchor = id
    case .toggle:
      if ids.remove(id) == nil { ids.insert(id) }
      anchor = id
    case .range:
      guard let anchor, let start = items.firstIndex(where: { $0.id == anchor }),
        let end = items.firstIndex(where: { $0.id == id })
      else { return click(id, .plain, in: items) }
      ids.formUnion(items[min(start, end)...max(start, end)].filter(\.canSend).map(\.id))
    }
    lead = id
  }

  package mutating func selectAll(in items: [BookItemViewModel]) {
    let sendable = items.filter(\.canSend)
    ids = Set(sendable.map(\.id))
    anchor = sendable.first?.id
    lead = sendable.last?.id
  }

  package mutating func clear() {
    ids = []
    anchor = nil
    lead = nil
  }

  /// Selects the next sendable book that way; up and down move whole rows of `columns`, so
  /// they stay in the column. At the end only the lead stays selected.
  package mutating func move(
    _ direction: MoveDirection, columns: Int, in items: [BookItemViewModel]
  ) {
    let step =
      switch direction {
      case .left: -1
      case .right: 1
      case .up: -max(columns, 1)
      case .down: max(columns, 1)
      }
    let current = lead.flatMap { lead in items.firstIndex { $0.id == lead } }
    var index = current.map { $0 + step } ?? (step > 0 ? 0 : items.count - 1)
    while items.indices.contains(index), !items[index].canSend {
      index += step
    }
    guard items.indices.contains(index) else {
      if let lead, ids.contains(lead) { select(lead) }
      return
    }
    select(items[index].id)
  }

  /// Drops books the filter now hides or the destination can't take.
  package mutating func keep(in items: [BookItemViewModel]) {
    ids.formIntersection(items.filter(\.canSend).map(\.id))
    if let anchor, !items.contains(where: { $0.id == anchor }) { self.anchor = nil }
    if let lead, !items.contains(where: { $0.id == lead }) { self.lead = nil }
  }

  private mutating func select(_ id: BookID) {
    ids = [id]
    anchor = id
    lead = id
  }
}
