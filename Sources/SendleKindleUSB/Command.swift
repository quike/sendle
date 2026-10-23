import Foundation
import SendleDomain
import os

/// Runs a command to its end, or stops it after a timeout or when the calling task is cancelled.
enum Command {
  enum Outcome: Equatable {
    case exited(Int32)
    case timedOut
    case cancelled
    case failedToStart(String)
  }

  /// Standard output and standard error both go to `log`.
  static func run(
    _ executable: URL,
    _ arguments: [String],
    log: URL,
    timeout: Duration
  ) async throws(SendFailure) -> Outcome {
    guard FileManager.default.createFile(atPath: log.path, contents: nil),
      let output = try? FileHandle(forWritingTo: log)
    else { throw .localStorage("Couldn't create \(log.lastPathComponent).") }
    defer { try? output.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = output
    let running = Running(process)

    let timer = Task {
      try? await Task.sleep(for: timeout)
      if !Task.isCancelled { running.stop(.timedOut) }
    }
    defer { timer.cancel() }
    return await withTaskCancellationHandler {
      await running.start()
    } onCancel: {
      running.stop(.cancelled)
    }
  }
}

/// A process that may be stopped from another thread, even before it has started. The first
/// outcome wins: a stop that comes after the exit changes nothing.
private final class Running: @unchecked Sendable {
  private let process: Process
  private let outcome = OSAllocatedUnfairLock<Command.Outcome?>(initialState: nil)

  init(_ process: Process) {
    self.process = process
  }

  func start() async -> Command.Outcome {
    let outcome = outcome
    return await withCheckedContinuation { continuation in
      process.terminationHandler = { process in
        continuation.resume(returning: Self.settle(outcome, .exited(process.terminationStatus)))
      }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(
          returning: Self.settle(outcome, .failedToStart(error.localizedDescription)))
        return
      }
      // A stop that came before the launch found nothing to end.
      if outcome.withLock({ $0 }) != nil { process.terminate() }
    }
  }

  func stop(_ why: Command.Outcome) {
    if Self.settle(outcome, why) == why, process.isRunning { process.terminate() }
  }

  private static func settle(
    _ outcome: OSAllocatedUnfairLock<Command.Outcome?>,
    _ candidate: Command.Outcome
  ) -> Command.Outcome {
    outcome.withLock { current in
      if current == nil { current = candidate }
      return current ?? candidate
    }
  }
}
