import Darwin
import Foundation

struct LoopbackError: Error {
  let call: String
}

/// A TCP server on 127.0.0.1 that accepts one connection and runs `script` on it.
final class LoopbackServer: Sendable {
  let port: Int
  private let listener: Int32

  init(_ script: @escaping @Sendable (Connection) -> Void) throws {
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    guard listener >= 0 else { throw LoopbackError(call: "socket") }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
        bind(listener, address, length) == 0 && listen(listener, 1) == 0
          && getsockname(listener, address, &length) == 0
      }
    }
    guard bound else {
      close(listener)
      throw LoopbackError(call: "bind")
    }
    port = Int(UInt16(bigEndian: address.sin_port))
    self.listener = listener
    Thread.detachNewThread {
      let client = accept(listener, nil, nil)
      guard client >= 0 else { return }
      script(Connection(descriptor: client))
      close(client)
    }
  }

  deinit {
    close(listener)
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
