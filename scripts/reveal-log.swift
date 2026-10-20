#!/usr/bin/env swift
// Prints a Takane release log with what its codes stand for: every `#k3f9qa` becomes
// `#k3f9qa‹value›`. Needs the log key the user sent privately (Settings › About › Share Logs).
//
// Usage: swift scripts/reveal-log.swift <log-file> <log-key>
//
// Mirrors LogKey, LogSecrets and LogLegend in app/Shared/Logging: the key's Crockford base32 text,
// its PBKDF2 salt and rounds, the HKDF purpose that derives the legend's key, and the legend section
// an export ends with. A change to any of them there needs the same change here.

import CommonCrypto
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("reveal-log: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let path = arguments.first, let keyText = arguments.last else {
    fail("usage: swift scripts/reveal-log.swift <log-file> <log-key>")
}
guard let log = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }

let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
var key = ""
for character in keyText.uppercased() where character != "-" && !character.isWhitespace {
    let digit: Character = switch character {
    case "O": "0"
    case "I", "L": "1"
    default: character
    }
    guard alphabet.contains(digit) else { fail("the log key has a character that is not in it: \(character)") }
    key.append(digit)
}
guard key.count == 12 else { fail("a log key has 12 characters, as XXXX-XXXX-XXXX") }

let salt = Array("takane-log-key-v1".utf8)
var stretched = [UInt8](repeating: 0, count: 32)
let status = CCKeyDerivationPBKDF(
    CCPBKDFAlgorithm(kCCPBKDF2), key, key.utf8.count, salt, salt.count,
    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &stretched, stretched.count
)
guard status == kCCSuccess else { fail("PBKDF2 failed: \(status)") }

let marker = "\n--- legend (encrypted) ---\n"
guard let section = log.range(of: marker, options: .backwards) else { fail("\(path) has no legend; is it a release log export?") }
let sealed = log[section.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
guard let data = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: data) else { fail("the legend is damaged") }
let legendKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: stretched), info: Data("takane log legend v1".utf8), outputByteCount: 32
)
guard let json = try? AES.GCM.open(box, using: legendKey) else { fail("wrong log key: it does not open this log's legend") }
guard let legend = try? JSONDecoder().decode([String: String].self, from: json) else { fail("the legend is damaged") }

let revealed = String(log[..<section.lowerBound]).replacing(#/\#[a-z2-7]{6}/#) { match in
    let code = String(match.output)
    return legend[code].map { "\(code)‹\($0)›" } ?? code
}
print(revealed)
