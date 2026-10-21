import Foundation

/// A preference kept in `UserDefaults` under `key` as its raw value.
struct DeviceSetting<Value: RawRepresentable & Equatable & Sendable> where Value.RawValue == String {
    let key: String
    let path: WritableKeyPath<Preferences, Value>
    /// The value in effect given the stored one, nil when missing or unknown, and core's profile.
    let resolve: @Sendable (_ stored: Value?, _ profile: Profile) -> Value
}

/// Preferences core's profile has no key for, kept in `UserDefaults` on this device and laid over
/// the ones core holds. To add one, give `Preferences` the field and `entries` a `DeviceSetting`.
enum CoreDeviceSettings {
    private struct Entry {
        let read: (inout Preferences, UserDefaults, Profile) -> Void
        let write: (Preferences, UserDefaults, Profile) -> Void

        init<Value>(_ setting: DeviceSetting<Value>) {
            read = { preferences, defaults, profile in
                let stored = defaults.string(forKey: setting.key).flatMap(Value.init(rawValue:))
                preferences[keyPath: setting.path] = setting.resolve(stored, profile)
            }
            write = { preferences, defaults, profile in
                let value = preferences[keyPath: setting.path]
                // Storing the default would pin it, so a default that follows the profile could no longer change.
                if value == setting.resolve(nil, profile) {
                    defaults.removeObject(forKey: setting.key)
                } else {
                    defaults.set(value.rawValue, forKey: setting.key)
                }
            }
        }
    }

    private static var entries: [Entry] {
        [
            Entry(DeviceSetting(key: "skipSegmentSource", path: \.skipSegmentSource) { stored, profile in
                SkipSegmentSource.resolved(stored, hasPremium: profile.hasPremium)
            }),
        ]
    }

    static func read(into preferences: inout Preferences, from defaults: UserDefaults, for profile: Profile) {
        entries.forEach { $0.read(&preferences, defaults, profile) }
    }

    static func write(_ preferences: Preferences, into defaults: UserDefaults, for profile: Profile) {
        entries.forEach { $0.write(preferences, defaults, profile) }
    }
}
