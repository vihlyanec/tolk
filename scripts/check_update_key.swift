import Foundation
import CryptoKit

// A key-file path and a public key may be passed as arguments; the private material is never printed.
guard CommandLine.arguments.count == 3 else { exit(2) }
do {
    let encoded = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let bytes = Data(base64Encoded: encoded), [32, 64].contains(bytes.count) else { exit(3) }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(bytes.prefix(32)))
    guard key.publicKey.rawRepresentation.base64EncodedString() == CommandLine.arguments[2] else { exit(4) }
} catch { exit(5) }
