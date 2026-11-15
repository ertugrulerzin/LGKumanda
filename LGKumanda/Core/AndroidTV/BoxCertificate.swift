import Foundation
import Security
import CryptoKit

/// The client identity the Android TV box pairs with: an RSA key and a self-signed certificate kept in the keychain.
/// The box remembers this certificate after pairing, so it must stay the same across launches.
enum BoxCertificate {
    static let label = "com.ertugrul.LGKumanda.androidtv"
    private static let keyTag = Data("com.ertugrul.LGKumanda.androidtv.key".utf8)

    enum Failure: LocalizedError {
        case keychain(OSStatus), key, signature
        var errorDescription: String? {
            switch self {
            case .keychain(let status): return "Kumanda kimliği kaydedilemedi (\(status))."
            case .key: return "Kumanda anahtarı oluşturulamadı."
            case .signature: return "Kumanda sertifikası imzalanamadı."
            }
        }
    }

    /// Returns the stored identity, creating the key and certificate on first use.
    static func identity() throws -> SecIdentity {
        if let existing = storedIdentity() { return existing }
        try reset()
        let key = try makeKey()
        let certificate = try makeCertificate(privateKey: key)
        let add: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: certificate,
                                  kSecAttrLabel as String: label]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.keychain(status) }
        guard let identity = storedIdentity() else { throw Failure.keychain(errSecItemNotFound) }
        return identity
    }

    /// Our certificate, for the pairing secret.
    static func certificate() throws -> SecCertificate {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(try identity(), &certificate)
        guard status == errSecSuccess, let certificate else { throw Failure.keychain(status) }
        return certificate
    }

    static func reset() throws {
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag] as CFDictionary)
    }

    private static func storedIdentity() -> SecIdentity? {
        let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: label,
                                    kSecReturnRef as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else { return nil }
        return (item as! SecIdentity)
    }

    private static func makeKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: keyTag,
                                            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw Failure.key }
        return key
    }

    /// Builds a minimal X.509 v3 certificate (CN=atvremote) signed with the key itself.
    private static func makeCertificate(privateKey: SecKey) throws -> SecCertificate {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw Failure.key }
        let sha256WithRSA = DER.sequence([DER.oid([1, 2, 840, 113549, 1, 1, 11]), DER.null])
        let name = DER.sequence([DER.set([DER.sequence([DER.oid([2, 5, 4, 3]), DER.utf8("atvremote")])])])
        let now = Date()
        let validity = DER.sequence([DER.time(now.addingTimeInterval(-86_400)), DER.time(now.addingTimeInterval(20 * 365 * 86_400))])
        let spki = DER.sequence([DER.sequence([DER.oid([1, 2, 840, 113549, 1, 1, 1]), DER.null]), DER.bitString(pkcs1)])
        var serial = Data((0..<8).map { _ in UInt8.random(in: 0...255) }); serial[0] &= 0x7F; serial[0] |= 0x01
        let tbs = DER.sequence([DER.explicit(0, DER.integer(Data([2]))), DER.integer(serial), sha256WithRSA,
                                name, validity, name, spki])
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error) as Data? else {
            throw Failure.signature
        }
        let der = DER.sequence([tbs, sha256WithRSA, DER.bitString(signature)])
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw Failure.signature }
        return certificate
    }

    /// RSA modulus and exponent of a certificate's key, as minimal big-endian bytes (no sign padding).
    static func rsaNumbers(_ certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let key = SecCertificateCopyKey(certificate),
              let pkcs1 = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return DER.rsaPublicKey(pkcs1)
    }

    /// The pairing secret: SHA-256 over both keys and the last four hex digits of the code shown on the box.
    /// Its first byte must equal the code's first two hex digits, which also catches typos.
    static func pairingSecret(code: String, client: (modulus: Data, exponent: Data),
                              server: (modulus: Data, exponent: Data)) -> Data? {
        let code = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6, let check = UInt8(code.prefix(2), radix: 16), let tail = Data(hex: String(code.dropFirst(2))) else { return nil }
        var hash = SHA256()
        for part in [client.modulus, client.exponent, server.modulus, server.exponent, tail] { hash.update(data: part) }
        let digest = Data(hash.finalize())
        return digest.first == check ? digest : nil
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        self.init(bytes)
    }
}

/// Just enough DER to write a certificate and read an RSA public key.
enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 { out.append(UInt8(n)) }
        else {
            var len = Data(); var v = n
            while v > 0 { len.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
            out.append(0x80 | UInt8(len.count)); out.append(len)
        }
        out.append(content)
        return out
    }
    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }
    static func set(_ items: [Data]) -> Data { tlv(0x31, items.reduce(Data(), +)) }
    static func explicit(_ tag: UInt8, _ content: Data) -> Data { tlv(0xA0 | tag, content) }
    static let null = Data([0x05, 0x00])
    static func integer(_ bytes: Data) -> Data {
        var b = bytes
        while b.count > 1, b.first == 0, (b[b.startIndex + 1] & 0x80) == 0 { b.removeFirst() }
        if let first = b.first, first & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, b)
    }
    static func utf8(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func bitString(_ bytes: Data) -> Data { tlv(0x03, Data([0]) + bytes) }
    static func oid(_ parts: [UInt]) -> Data {
        var out = Data([UInt8(parts[0] * 40 + parts[1])])
        for var part in parts.dropFirst(2) {
            var chunk = [UInt8(part & 0x7F)]; part >>= 7
            while part > 0 { chunk.insert(UInt8(part & 0x7F) | 0x80, at: 0); part >>= 7 }
            out.append(contentsOf: chunk)
        }
        return tlv(0x06, out)
    }
    static func time(_ date: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(f.string(from: date).utf8))
    }
    /// Parses PKCS#1 RSAPublicKey: SEQUENCE { modulus INTEGER, publicExponent INTEGER }.
    static func rsaPublicKey(_ der: Data) -> (modulus: Data, exponent: Data)? {
        var i = der.startIndex
        guard read(der, &i, tag: 0x30) != nil else { return nil }
        guard let modulus = read(der, &i, tag: 0x02), let exponent = read(der, &i, tag: 0x02) else { return nil }
        func trimmed(_ d: Data) -> Data { let t = d.drop { $0 == 0 }; return t.isEmpty ? Data([0]) : Data(t) }
        return (trimmed(modulus), trimmed(exponent))
    }
    /// Reads one TLV header; for SEQUENCE it enters the container (returns its range length only).
    private static func read(_ d: Data, _ i: inout Data.Index, tag: UInt8) -> Data? {
        guard i < d.endIndex, d[i] == tag else { return nil }
        i += 1
        guard i < d.endIndex else { return nil }
        var length = Int(d[i]); i += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count <= 4, d.endIndex - i >= count else { return nil }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(d[i]); i += 1 }
        }
        guard d.endIndex - i >= length else { return nil }
        if tag == 0x30 { return Data() }
        let value = d.subdata(in: i..<(i + length)); i += length
        return value
    }
}
