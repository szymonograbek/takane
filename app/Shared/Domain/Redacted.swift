import Foundation

/// Gives each text a short code, `#k3f9qa`: the same for equal texts, different for different ones,
/// and not reversible by whoever reads it.
struct Pseudonymizer: Sendable {
    let code: @Sendable (String) -> String
}

/// How text renderings of `Redacted` values and other personal values show them. Outside log lines
/// they show as they are, so text built for the screen reads real values. `Log` renders every line
/// under the build's: revealed in debug builds, so local development reads real values, and
/// pseudonymized in release ones, so logs a user shares name nothing personal yet still show when
/// two lines are about the same value.
enum Redaction: Sendable {
    case revealed
    case pseudonymized(Pseudonymizer)

    /// Tests read release text with `Redaction.$current.withValue(.pseudonymized(…))`.
    @TaskLocal static var current: Redaction = .revealed

    /// `text` itself, or its code.
    func text(_ text: String) -> String {
        switch self {
        case .revealed: text
        case .pseudonymized(let pseudonymizer): pseudonymizer.code(text)
        }
    }
}

/// A value that identifies the user, grants access or says what the user chose to use or watch: an
/// add-on link carrying a debrid key, the account's email, a sign-in code, a stream's address, an
/// add-on's name, a title's name, a file name. Interpolating it, as every log line does, shows the
/// value in debug builds and a code standing for it in release ones. Code that needs the value
/// itself (a request, text the user must read) asks for `rawValue`.
struct Redacted<Value: Hashable & Sendable>: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let rawValue: Value

    init(_ rawValue: Value) {
        self.rawValue = rawValue
    }

    var description: String { text(in: .current) }
    var debugDescription: String { description }

    func text(in redaction: Redaction) -> String {
        redaction.text(String(describing: rawValue))
    }
}

extension Redacted: Decodable where Value: Decodable {
    init(from decoder: any Decoder) throws {
        self.init(try Value(from: decoder))
    }
}
