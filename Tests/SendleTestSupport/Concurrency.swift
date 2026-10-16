/// Collects values produced from concurrent code, in arrival order.
public actor Recorder<Element: Sendable> {
  public private(set) var values: [Element] = []

  public init() {}

  public func record(_ value: Element) {
    values.append(value)
  }
}

/// A one-shot flag a test can wait on.
public actor Signal {
  private var isFired = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func fire() {
    isFired = true
    for waiter in waiters {
      waiter.resume()
    }
    waiters.removeAll()
  }

  public func wait() async {
    guard !isFired else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

/// Polls `condition` until it holds or five seconds pass, for state other tasks update.
@MainActor
public func eventually(_ condition: () -> Bool) async -> Bool {
  for _ in 0..<500 {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return condition()
}
