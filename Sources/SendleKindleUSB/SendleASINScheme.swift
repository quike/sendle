import SendleDomain

public struct SendleASINScheme: ASINScheme {
  public init() {}

  public func asin(forSeed seed: String) -> String {
    AZW3Metadata.asin(for: seed)
  }
}
