import Foundation
import Testing
import TaktCore

@Test func updateConfigurationRequiresHTTPSAndFullEd25519PublicKey() {
    let publicKey = Data(repeating: 42, count: 32).base64EncodedString()
    #expect(UpdateConfiguration(feedURL: "https://github.com/example/tolk/releases/latest/download/appcast.xml", publicKey: publicKey) != nil)
    for url in [nil, "", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:password@example.com/appcast.xml"] as [String?] {
        #expect(UpdateConfiguration(feedURL: url, publicKey: publicKey) == nil)
    }
    #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "bad") == nil)
    #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: Data(repeating: 42, count: 31).base64EncodedString()) == nil)
}
