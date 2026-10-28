// Explicit one-time setup. Creates an application-signing key in
// login Keychain; never exports private material or touches the Sparkle key.
import Foundation
import Security
import CryptoKit

func fail(_ text: String) -> Never { FileHandle.standardError.write(Data((text + "\n").utf8)); exit(1) }
func der(_ tag: UInt8, _ content: Data) -> Data {
    var length = content.count, bytes: [UInt8] = []
    if length < 128 { bytes = [UInt8(length)] }
    else {
        while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }
        bytes.insert(0x80 | UInt8(bytes.count), at: 0)
    }
    return Data([tag] + bytes) + content
}
func sequence(_ values: Data...) -> Data { der(0x30, values.reduce(Data(), +)) }
func oid(_ bytes: [UInt8]) -> Data { der(6, Data(bytes)) }
func bitString(_ data: Data) -> Data { der(3, Data([0]) + data) }
func extensionValue(_ id: [UInt8], _ value: Data, critical: Bool = false) -> Data {
    sequence(oid(id), critical ? Data([1, 1, 255]) : Data(), der(4, value))
}
let label = "Tolk Application Signing"
let tag = Data("local.tolk.application-signing.v1".utf8)
guard CommandLine.arguments.count == 2 else { fail("Usage: swift setup_code_signing.swift /absolute/path/app-signing.json") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let previous: [String: String]?
if FileManager.default.fileExists(atPath: output.path) {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: String] else { fail("Invalid existing signing configuration; it was not replaced") }
    previous = value
} else { previous = nil }
var existing: CFTypeRef?
let certificateStatus = SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecAttrLabel: label, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &existing)
var certificate: SecCertificate
if certificateStatus == errSecSuccess, let existing {
    certificate = existing as! SecCertificate
} else {
    guard certificateStatus == errSecItemNotFound else { fail("Cannot query signing certificate: \(certificateStatus)") }
    guard previous == nil else { fail("Pinned certificate is absent from Keychain; restore it instead of creating a replacement") }
    var keyResult: CFTypeRef?
    let keyStatus = SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag, kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecReturnRef: true] as CFDictionary, &keyResult)
    let privateKey: SecKey
    if keyStatus == errSecSuccess, let keyResult { privateKey = keyResult as! SecKey }
    else {
        guard keyStatus == errSecItemNotFound else { fail("Cannot query signing key: \(keyStatus)") }
        var trusted: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &trusted) == errSecSuccess, let trusted else { fail("Cannot identify Apple's codesign tool") }
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, [trusted] as CFArray, &access) == errSecSuccess, let access else { fail("Cannot create signing key access policy") }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 3072,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrIsExtractable: false,
                kSecAttrApplicationTag: tag, kSecAttrLabel: label, kSecAttrAccess: access]]
        var error: Unmanaged<CFError>?
        guard let created = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { fail("Cannot create signing key in Keychain") }
        privateKey = created
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey), let publicBytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { fail("Cannot read public key") }
    let algorithm = sequence(oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,0x0b]), Data([5,0]))
    let name = sequence(der(0x31, sequence(oid([0x55,4,3]), der(12, Data(label.utf8)))))
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyMMddHHmmss'Z'"
    let now = Date(), expires = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: now)!
    let validity = sequence(der(23, Data(formatter.string(from: now.addingTimeInterval(-86400)).utf8)), der(23, Data(formatter.string(from: expires).utf8)))
    let spki = sequence(sequence(oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,1]), Data([5,0])), bitString(publicBytes))
    var serial = [UInt8](repeating: 0, count: 16)
    guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else { fail("Cannot generate certificate serial") }
    serial[0] = (serial[0] & 0x7f) | 1
    let extensions = sequence(extensionValue([0x55,0x1d,0x13], sequence(), critical: true),
        extensionValue([0x55,0x1d,0x0f], Data([3,2,7,0x80]), critical: true),
        extensionValue([0x55,0x1d,0x25], sequence(oid([0x2b,6,1,5,5,7,3,3]))))
    let tbs = sequence(der(0xa0, Data([2,1,2])), der(2, Data(serial)), algorithm, name, validity, name, spki, der(0xa3, extensions))
    guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, nil) as Data? else { fail("Cannot sign certificate using Keychain key") }
    let bytes = sequence(tbs, algorithm, bitString(signature))
    guard let created = SecCertificateCreateWithData(nil, bytes as CFData) else { fail("Cannot parse generated public certificate") }
    certificate = created
    let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: label] as CFDictionary, nil)
    guard status == errSecSuccess else { fail("Cannot save public certificate: \(status)") }
}
var identity: SecIdentity?
guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess else { fail("Signing certificate has no matching private key; it was not replaced") }
let bytes = SecCertificateCopyData(certificate) as Data
let sha1 = Insecure.SHA1.hash(data: bytes).map { String(format: "%02X", $0) }.joined()
let sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
let json: [String: String] = ["identity_sha1": sha1, "certificate_sha256": sha256, "name": label]
if let previous, previous != json { fail("Existing signing configuration differs; automatic key rotation is forbidden") }
// Trust is limited to code signing for this certificate in this user's domain.
// No SSL trust, system trust, TCC changes or Gatekeeper exceptions are installed.
guard let policy = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil) else { fail("Cannot create code-signing trust policy") }
var trust: SecTrust?
guard SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess, let trust else { fail("Cannot evaluate signing certificate") }
if !SecTrustEvaluateWithError(trust, nil) {
    let settings: [String: Any] = [kSecTrustSettingsPolicy: policy,
        kSecTrustSettingsResult: SecTrustSettingsResult.trustRoot.rawValue]
    let status = SecTrustSettingsSetTrustSettings(certificate, .user, settings as CFDictionary)
    guard status == errSecSuccess else { fail("User code-signing trust requires confirmation: \(status). No settings file written.") }
}
let encoded = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
if previous == nil { try encoded.write(to: output, options: .atomic) }
print("Permanent application-signing identity ready: \(sha1). Configuration contains public fingerprints only.")
