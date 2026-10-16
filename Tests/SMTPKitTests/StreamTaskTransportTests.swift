import Foundation
import SMTPKit
import Testing

@Suite(.timeLimit(.minutes(1)))
struct StreamTaskTransportTests {
  func transport(_ server: LoopbackServer) -> StreamTaskTransport {
    StreamTaskTransport(host: "127.0.0.1", port: server.port, implicitTLS: false)
  }

  @Test func readsAReplyThatArrivesInPieces() async throws {
    let server = try LoopbackServer { client in
      client.send("220-smtp.example.com\r\n")
      client.pause(0.1)
      client.send("220 ready\r\n")
    }
    let transport = transport(server)
    try await transport.open()

    let reply = try await transport.readReply(timeout: .seconds(5))

    #expect(reply == SMTPReply(code: 220, lines: ["smtp.example.com", "ready"]))
    await transport.close()
  }

  @Test func writesWhatTheServerReads() async throws {
    let server = try LoopbackServer { client in
      client.send("220 ready\r\n")
      client.send("250 hello \(client.readLine() ?? "")\r\n")
    }
    let transport = transport(server)
    try await transport.open()
    _ = try await transport.readReply(timeout: .seconds(5))

    try await transport.write(Data("EHLO [127.0.0.1]\r\n".utf8), timeout: .seconds(5))

    #expect(try await transport.readReply(timeout: .seconds(5)).text == "hello EHLO [127.0.0.1]")
    await transport.close()
  }

  @Test func timesOutWhenTheServerSaysNothing() async throws {
    let server = try LoopbackServer { client in client.pause(3) }
    let transport = transport(server)
    try await transport.open()

    await #expect(throws: SMTPTransportError.timedOut) {
      try await transport.readReply(timeout: .milliseconds(300))
    }
    await transport.close()
  }

  @Test func noticesWhenTheServerHangsUp() async throws {
    let server = try LoopbackServer { _ in }
    let transport = transport(server)
    try await transport.open()

    await #expect(throws: SMTPTransportError.closed) {
      try await transport.readReply(timeout: .seconds(5))
    }
    await transport.close()
  }

  @Test func stopsReadingAsSoonAsItsTaskIsCancelled() async throws {
    let server = try LoopbackServer { client in client.pause(5) }
    let transport = transport(server)
    try await transport.open()
    let started = ContinuousClock.now
    let read = Task { try await transport.readReply(timeout: .seconds(30)) }

    try await Task.sleep(for: .milliseconds(200))
    read.cancel()

    await #expect(throws: SMTPTransportError.cancelled) { try await read.value }
    #expect(ContinuousClock.now - started < .seconds(3))
    await transport.close()
  }

  @Test func failsWhenNothingListens() async throws {
    let transport = StreamTaskTransport(
      host: "127.0.0.1", port: try LoopbackServer.unusedPort(), implicitTLS: false)
    try await transport.open()

    await #expect {
      try await transport.readReply(timeout: .seconds(5))
    } throws: { error in
      if case .failed = error as? SMTPTransportError { true } else { false }
    }
    await transport.close()
  }
}
