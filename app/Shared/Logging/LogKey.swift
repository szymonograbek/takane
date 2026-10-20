import CommonCrypto
import CryptoKit
import Foundation
import Synchronization

/// The secret behind release logs' codes, one per install: 12 characters of Crockford's base32,
/// 60 random bits, read to the user as `K0FM-Q2XD-91NB`. Short, so the user can retype it from the
/// TV. Codes are keyed by it through `LogSecrets`, so nobody without it can tell which title or
/// add-on a code stands for, even by trying every IMDb id. An export carries the codes' values
/// sealed with it (the legend), so a user who hands the key over privately lets the maintainer read
/// them with `scripts/reveal-log.swift`, which derives the same keys.
struct LogKey: Equatable, Sendable {
    static let length = 12
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Uppercase, without dashes.
    let characters: String

    /// Parses `text` as the user types it: any case, with or without dashes and spaces, and with the
    /// look-alikes Crockford's base32 reads as digits (O as 0, I and L as 1).
    init?(text: String) {
        var characters = ""
        for character in text.uppercased() where character != "-" && !character.isWhitespace {
            let digit: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard Self.alphabet.contains(digit) else { return nil }
            characters.append(digit)
        }
        guard characters.count == Self.length else { return nil }
        self.characters = characters
    }

    static func random() -> LogKey {
        var generator = SystemRandomNumberGenerator()
        let characters = String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
        guard let key = LogKey(text: characters) else { preconditionFailure("made from the alphabet at the length") }
        return key
    }

    /// The install's, made on first use and kept in the user defaults, so codes stay the same across
    /// sessions and an export of several days still correlates. Deleting the app forgets it, and a
    /// stored value that is not a key, such as an earlier build's, is replaced.
    static func stored(in defaults: UserDefaults = .standard) -> LogKey {
        let name = "logKey"
        if let stored = defaults.string(forKey: name).flatMap(LogKey.init(text:)) {
            return stored
        }
        let key = random()
        defaults.set(key.characters, forKey: name)
        return key
    }

    /// Groups of 4: `K0FM-Q2XD-91NB`.
    var text: String {
        let characters = Array(characters)
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }
}

/// What a `LogKey` unlocks: the keys of codes and of the legend, derived from the key stretched with
/// PBKDF2. A shared log lets anyone test guesses offline, against its legend and against the codes of
/// values they can guess, and 60 bits are few enough to try at hash speed; stretching makes each
/// guess cost a fraction of a second. That cost is also the app's, so it is paid once, on a background
/// queue from `init`, and whatever needs the keys before then waits for them.
///
/// `scripts/reveal-log.swift` repeats the derivation and states these constants again.
final class LogSecrets: Sendable {
    static let salt = "takane-log-key-v1"
    static let rounds: UInt32 = 600_000

    private struct Keys: Sendable {
        let codes: SymmetricKey
        let legend: SymmetricKey
    }

    private let key: LogKey
    private let derived = Mutex<Keys?>(nil)

    init(_ key: LogKey) {
        self.key = key
        DispatchQueue.global(qos: .utility).async { [self] in _ = keys }
    }

    /// Codes are `#` and 6 lowercase base32 characters of the text's HMAC-SHA256: 30 bits, so two
    /// values in one log share a code only by a negligible chance.
    var pseudonymizer: Pseudonymizer {
        Pseudonymizer { [self] text in
            let mac = Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: keys.codes))
            return "#" + Base32.encode(mac).prefix(6).lowercased()
        }
    }

    /// `legend`, codes to the values they stand for, sealed with AES-GCM as base64.
    func seal(_ legend: [String: String]) -> String {
        do {
            let json = try JSONEncoder().encode(legend)
            guard let sealed = try AES.GCM.seal(json, using: keys.legend).combined else {
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
        guard let json = try? AES.GCM.open(box, using: keys.legend) else { throw .wrongKey }
        guard let legend = try? JSONDecoder().decode([String: String].self, from: json) else { throw .malformed }
        return legend
    }

    /// Holding the lock while deriving makes every other caller wait for the one derivation.
    private var keys: Keys {
        derived.withLock { derived in
            if let derived { return derived }
            let stretched = Self.stretch(key)
            let keys = Keys(codes: Self.subkey(from: stretched, for: "takane log codes v1"), legend: Self.subkey(from: stretched, for: "takane log legend v1"))
            derived = keys
            return keys
        }
    }

    private static func stretch(_ key: LogKey) -> SymmetricKey {
        let salt = Array(Self.salt.utf8)
        var stretched = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), key.characters, key.characters.utf8.count, salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &stretched, stretched.count
        )
        guard status == kCCSuccess else { preconditionFailure("PBKDF2 refused its fixed parameters: \(status)") }
        return SymmetricKey(data: stretched)
    }

    private static func subkey(from stretched: SymmetricKey, for purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: stretched, info: Data(purpose.utf8), outputByteCount: 32)
    }
}

enum LegendError: Error, Equatable {
    /// Not a legend this app sealed.
    case malformed
    /// Sealed with another key.
    case wrongKey
}

/// RFC 4648 base32 without padding, the alphabet of codes.
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
}
