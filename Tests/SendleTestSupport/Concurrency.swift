import Foundation

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
  private var cancellableWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

  public init() {}

  public func fire() {
    isFired = true
    for waiter in waiters {
      waiter.resume()
    }
    waiters.removeAll()
    for waiter in cancellableWaiters.values {
      waiter.resume(returning: true)
    }
    cancellableWaiters.removeAll()
  }

  public func wait() async {
    guard !isFired else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  /// Waits for the signal, or gives up with false when the waiting task is cancelled.
  public func waitUnlessCancelled() async -> Bool {
    guard !isFired else { return true }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (waiter: CheckedContinuation<Bool, Never>) in
        if Task.isCancelled {
          waiter.resume(returning: false)
        } else {
          cancellableWaiters[id] = waiter
        }
      }
    } onCancel: {
      Task { await self.giveUp(id) }
    }
  }

  private func giveUp(_ id: UUID) {
    cancellableWaiters.removeValue(forKey: id)?.resume(returning: false)
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
