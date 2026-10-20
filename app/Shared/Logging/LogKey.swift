import CryptoKit
import Foundation

/// The secret behind release logs' codes, one per install: 16 random bytes, read to the user as
/// `K7FM-Q2XD-…`. Codes are keyed by it, so nobody without it can tell which title or add-on a code
/// stands for, even by trying every IMDb id. An export carries the codes' values sealed with it
/// (the legend), so a user who hands the key over privately lets the maintainer read them with
/// `scripts/reveal-log.swift`, which derives the same keys.
struct LogKey: Equatable, Sendable {
    static let byteCount = 16

    let bytes: Data

    init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    /// Parses `text` as `text` shows it, ignoring letter case, dashes and spaces.
    init?(text: String) {
        let characters = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard let bytes = Base32.decode(characters, byteCount: Self.byteCount) else { return nil }
        self.bytes = bytes
    }

    static func random() -> LogKey {
        let bytes = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        guard let key = LogKey(bytes: bytes) else { preconditionFailure("128 bits are 16 bytes") }
        return key
    }

    /// The install's, made on first use and kept in the user defaults, so codes stay the same across
    /// sessions and an export of several days still correlates. Deleting the app forgets it.
    static func stored(in defaults: UserDefaults = .standard) -> LogKey {
        let name = "logKey"
        if let stored = defaults.data(forKey: name).flatMap(LogKey.init(bytes:)) {
            return stored
        }
        let key = random()
        defaults.set(key.bytes, forKey: name)
        return key
    }

    /// Uppercase base32 in groups of 4: `K7FM-Q2XD-…`, 26 characters.
    var text: String {
        let characters = Array(Base32.encode(bytes))
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }

    /// Codes are `#` and 6 lowercase base32 characters of the text's HMAC-SHA256: 30 bits, so two
    /// values in one log share a code only by a negligible chance.
    var pseudonymizer: Pseudonymizer {
        let key = derived("takane log codes v1")
        return Pseudonymizer { text in
            let mac = Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: key))
            return "#" + Base32.encode(mac).prefix(6).lowercased()
        }
    }

    /// `legend`, codes to the values they stand for, sealed with AES-GCM as base64.
    func seal(_ legend: [String: String]) -> String {
        do {
            let json = try JSONEncoder().encode(legend)
            guard let sealed = try AES.GCM.seal(json, using: derived("takane log legend v1")).combined else {
                preconditionFailure("the default nonce is 12 bytes")
            }
            return sealed.base64EncodedString()
        } catch {
            preconditionFailure("sealing a string map cannot fail: \(error)")
        }
    }

    func open(_ sealed: String) throws(LegendError) -> [String: String] {
        guard let data = Data(base64Encoded: sealed.trimmingCharacters(in: .whitespacesAndNewlines)),
              let box = try? AES.GCM.SealedBox(combined: data)
        else { throw .malformed }
        guard let json = try? AES.GCM.open(box, using: derived("takane log legend v1")) else { throw .wrongKey }
        guard let legend = try? JSONDecoder().decode([String: String].self, from: json) else { throw .malformed }
        return legend
    }

    private func derived(_ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), info: Data(purpose.utf8), outputByteCount: 32)
    }
}

enum LegendError: Error, Equatable {
    /// Not a legend this app sealed.
    case malformed
    /// Sealed with another key.
    case wrongKey
}

/// RFC 4648 base32 without padding.
private enum Base32 {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ bytes: Data) -> String {
        var characters: [Character] = []
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8 | Int(byte)) & 0xFFFF
            bits += 8
            while bits >= 5 {
                bits -= 5
                characters.append(alphabet[buffer >> bits & 31])
            }
        }
        if bits > 0 {
            characters.append(alphabet[buffer << (5 - bits) & 31])
        }
        return String(characters)
    }

    /// Nil unless `text` is exactly `byteCount` bytes in uppercase base32.
    static func decode(_ text: String, byteCount: Int) -> Data? {
        guard text.count == (byteCount * 8 + 4) / 5 else { return nil }
        var bytes = Data()
        var buffer = 0
        var bits = 0
        for character in text {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5 | value) & 0xFFFF
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8(buffer >> bits & 0xFF))
            }
        }
        return bytes.count == byteCount ? bytes : nil
    }
}
