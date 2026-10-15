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
