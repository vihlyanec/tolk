import Foundation

public struct UpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL
    public let publicKey: String
    public init?(feedURL: String?, publicKey: String?) {
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil,
              let publicKey, let decoded = Data(base64Encoded: publicKey), decoded.count == 32 else { return nil }
        self.feedURL = url; self.publicKey = publicKey
    }
}
