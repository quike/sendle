import Foundation
import SendleDomain

public struct HTTPReply: Sendable {
  public let status: Int
  public let data: Data

  public init(status: Int, data: Data) {
    self.status = status
    self.data = data
  }
}

/// A GET that follows redirects and tells how it went in `LookupError`s.
public protocol HTTPFetching: Sendable {
  func get(_ url: URL) async throws(LookupError) -> HTTPReply
}

/// Reaches the catalogues over HTTPS with Sendle's User-Agent and nothing kept between requests.
public struct URLSessionFetcher: HTTPFetching {
  private let session: URLSession
  private let userAgent: String
  private let log: any ActivityLog

  public init(userAgent: String, log: any ActivityLog) {
    self.init(configuration: .ephemeral, userAgent: userAgent, log: log)
  }

  package init(configuration: URLSessionConfiguration, userAgent: String, log: any ActivityLog) {
    configuration.timeoutIntervalForRequest = 10
    session = URLSession(configuration: configuration)
    self.userAgent = userAgent
    self.log = log
  }

  public func get(_ url: URL) async throws(LookupError) -> HTTPReply {
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      throw Self.error(for: error)
    } catch {
      throw .unreadable
    }
    guard let http = response as? HTTPURLResponse else { throw .unreadable }
    log.debug(.lookup, "GET \(url.host() ?? "")\(url.path) → \(http.statusCode)")
    return HTTPReply(status: http.statusCode, data: data)
  }

  package static func error(for error: URLError) -> LookupError {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost:
      .offline
    case .timedOut:
      .timedOut
    default:
      .unreadable
    }
  }
}
