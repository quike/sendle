import Foundation
import SendleDomain
import SendleLookup
import SendleTestSupport
import Testing
import os

@Suite(.timeLimit(.minutes(1)))
struct URLSessionFetcherTests {
  let log = FakeActivityLog()

  func fetcher() -> URLSessionFetcher {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSessionFetcher(
      configuration: configuration, userAgent: "Sendle/test (+https://example.test)", log: log)
  }

  func stub(_ url: String, _ behaviour: StubURLProtocol.Behaviour) throws -> URL {
    StubURLProtocol.behaviours.withLock { $0[url] = behaviour }
    return try #require(URL(string: url))
  }

  @Test func urlErrorsMapToLookupErrors() {
    for code: URLError.Code in [
      .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
    ] {
      #expect(URLSessionFetcher.error(for: URLError(code)) == .offline)
    }
    #expect(URLSessionFetcher.error(for: URLError(.timedOut)) == .timedOut)
    #expect(URLSessionFetcher.error(for: URLError(.cancelled)) == .unreadable)
    #expect(URLSessionFetcher.error(for: URLError(.badServerResponse)) == .unreadable)
  }

  @Test func repliesWithTheStatusAndBody() async throws {
    let url = try stub("https://stub.test/body", .reply(status: 404, body: Data("gone".utf8)))
    let reply = try await fetcher().get(url)
    #expect(reply.status == 404)
    #expect(String(decoding: reply.data, as: UTF8.self) == "gone")
  }

  @Test func sendsItsUserAgent() async throws {
    let url = try stub("https://stub.test/agent", .reply(status: 200, body: Data()))
    _ = try await fetcher().get(url)
    #expect(
      StubURLProtocol.userAgents.withLock { $0[url.absoluteString] }
        == "Sendle/test (+https://example.test)")
  }

  @Test func followsRedirects() async throws {
    let target = try stub(
      "https://stub.test/books/1.json", .reply(status: 200, body: Data("x".utf8)))
    let url = try stub("https://stub.test/isbn/1.json", .redirect(to: target))
    let reply = try await fetcher().get(url)
    #expect(reply.status == 200)
    #expect(reply.data == Data("x".utf8))
  }

  @Test func logsHostPathAndStatusButNeverTheQuery() async throws {
    let url = try stub(
      "https://stub.test/search.json?title=Secret%20Title&key=hunter2",
      .reply(status: 429, body: Data()))
    _ = try await fetcher().get(url)
    #expect(log.summary == ["debug LOOKUP GET stub.test/search.json → 429"])
  }

  @Test func transportFailuresBecomeLookupErrors() async throws {
    let url = try stub("https://stub.test/offline", .fail(.notConnectedToInternet))
    await #expect(throws: LookupError.offline) { try await fetcher().get(url) }
    #expect(log.summary == [])
  }
}

/// Serves what the test registered for a URL, and notes the User-Agent it came with.
final class StubURLProtocol: URLProtocol {
  enum Behaviour: Sendable {
    case reply(status: Int, body: Data)
    case redirect(to: URL)
    case fail(URLError.Code)
  }

  static let behaviours = OSAllocatedUnfairLock<[String: Behaviour]>(initialState: [:])
  static let userAgents = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let url = request.url,
      let behaviour = Self.behaviours.withLock({ $0[url.absoluteString] })
    else { return finish(with: URLError(.unsupportedURL)) }
    let userAgent = request.value(forHTTPHeaderField: "User-Agent")
    Self.userAgents.withLock { $0[url.absoluteString] = userAgent }
    switch behaviour {
    case .reply(let status, let body):
      guard
        let response = HTTPURLResponse(
          url: url, statusCode: status, httpVersion: nil, headerFields: nil)
      else { return finish(with: URLError(.badServerResponse)) }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .redirect(let target):
      guard
        let response = HTTPURLResponse(
          url: url, statusCode: 302, httpVersion: nil,
          headerFields: ["Location": target.absoluteString])
      else { return finish(with: URLError(.badServerResponse)) }
      client?.urlProtocol(
        self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
    case .fail(let code):
      finish(with: URLError(code))
    }
  }

  private func finish(with error: URLError) {
    client?.urlProtocol(self, didFailWithError: error)
  }
}
