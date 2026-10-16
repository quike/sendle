import Darwin
import Foundation

struct LoopbackError: Error {
  let call: String
}

/// A TCP server on 127.0.0.1 that accepts one connection and runs `script` on it.
final class LoopbackServer: Sendable {
  let port: Int
  /// Closing it stops the accept thread, which owns and closes every other descriptor, so no
  /// descriptor is used after its number may belong to another test.
  private let stop: Int32

  init(_ script: @escaping @Sendable (Connection) -> Void) throws {
    let (listener, port) = try Self.bound()
    var ends: [Int32] = [0, 0]
    guard listen(listener, 1) == 0 else {
      close(listener)
      throw LoopbackError(call: "listen")
    }
    guard pipe(&ends) == 0 else {
      close(listener)
      throw LoopbackError(call: "pipe")
    }
    self.port = port
    stop = ends[1]
    let stopped = ends[0]
    Thread.detachNewThread {
      var waits = [listener, stopped].map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
      let ready = poll(&waits, 2, -1) > 0 && waits[1].revents == 0
      let client = ready ? accept(listener, nil, nil) : -1
      close(listener)
      close(stopped)
      guard client >= 0 else { return }
      var on: Int32 = 1
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
      script(Connection(descriptor: client))
      close(client)
    }
  }

  deinit {
    close(stop)
  }

  /// A port on 127.0.0.1 that nothing listens on.
  static func unusedPort() throws -> Int {
    let (descriptor, port) = try bound()
    close(descriptor)
    return port
  }

  /// A socket bound to a free port on 127.0.0.1.
  private static func bound() throws -> (descriptor: Int32, port: Int) {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LoopbackError(call: "socket") }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
        bind(descriptor, address, length) == 0 && getsockname(descriptor, address, &length) == 0
      }
    }
    guard bound else {
      close(descriptor)
      throw LoopbackError(call: "bind")
    }
    return (descriptor, Int(UInt16(bigEndian: address.sin_port)))
  }

  struct Connection: Sendable {
    let descriptor: Int32

    func send(_ text: String) {
      _ = Array(text.utf8).withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    /// The next line the client sent, without its CRLF.
    func readLine() -> String? {
      var line: [UInt8] = []
      var byte: UInt8 = 0
      while read(descriptor, &byte, 1) == 1 {
        if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
        if byte != 0x0D { line.append(byte) }
      }
      return nil
    }

    func pause(_ seconds: Double) {
      Thread.sleep(forTimeInterval: seconds)
    }
  }
}
