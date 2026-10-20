#!/usr/bin/env swift
// Prints a Takane release log with what its codes stand for: every `#k3f9qa` becomes
// `#k3f9qa‹value›`. Needs the log key the user sent privately (Settings › About › Share Logs).
//
// Usage: swift scripts/reveal-log.swift <log-file> <log-key>
//
// Mirrors LogKey and LogLegend in app/Shared/Logging: the key's base32 text, the HKDF purpose that
// derives the legend's key, and the legend section an export ends with.

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

let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
let characters = keyText.uppercased().filter { $0 != "-" && !$0.isWhitespace }
var keyBytes = Data()
var buffer = 0
var bits = 0
for character in characters {
    guard let value = alphabet.firstIndex(of: character) else { fail("the log key has a character that is not in it: \(character)") }
    buffer = (buffer << 5 | value) & 0xFFFF
    bits += 5
    if bits >= 8 {
        bits -= 8
        keyBytes.append(UInt8(buffer >> bits & 0xFF))
    }
}
guard characters.count == 26, keyBytes.count == 16 else { fail("a log key has 26 characters, as XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX") }

let marker = "\n--- legend (encrypted) ---\n"
guard let section = log.range(of: marker, options: .backwards) else { fail("\(path) has no legend; is it a release log export?") }
let sealed = log[section.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
guard let data = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: data) else { fail("the legend is damaged") }
let legendKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: keyBytes), info: Data("takane log legend v1".utf8), outputByteCount: 32
)
guard let json = try? AES.GCM.open(box, using: legendKey) else { fail("wrong log key: it does not open this log's legend") }
guard let legend = try? JSONDecoder().decode([String: String].self, from: json) else { fail("the legend is damaged") }

let revealed = String(log[..<section.lowerBound]).replacing(#/\#[a-z2-7]{6}/#) { match in
    let code = String(match.output)
    return legend[code].map { "\(code)‹\($0)›" } ?? code
}
print(revealed)
