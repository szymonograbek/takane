/// An add-on in the user's profile.
struct InstalledAddon: Identifiable, Hashable, Sendable {
    let manifestURL: ManifestURL
    /// Names the add-on the user chose, which release logs keep private.
    let name: Redacted<String>
    let version: String
    /// False for add-ons the provider keeps installed, such as its official catalog.
    let isRemovable: Bool
    /// False when switched off on this device only: it stays installed, and the app asks it for nothing here.
    let isEnabled: Bool

    var id: ManifestURL { manifestURL }
}

enum AddonError: Error, Equatable, Sendable {
    /// The manifest could not be fetched or parsed.
    case manifestUnavailable(reason: String)
    case timedOut(stage: String)
    /// The provider refused the request outright.
    case rejected(reason: String)
}

/// Installs add-ons, reports which are installed, orders them and switches them on or off on this device.
protocol AddonService: Sendable {
    /// The installed add-ons now, in the account's order, then after every change.
    func installed() -> AsyncStream<[InstalledAddon]>

    /// Fetches the manifest and installs it. Installing an installed add-on returns it unchanged.
    func install(_ manifest: ManifestURL) async throws(AddonError) -> InstalledAddon

    /// Removing an add-on that is not installed does nothing.
    func uninstall(_ manifest: ManifestURL) async throws(AddonError)

    /// Switches the add-on on or off on this device only. It stays installed, so the account and
    /// other devices keep it as it was.
    func setEnabled(_ manifest: ManifestURL, _ isEnabled: Bool) async throws(AddonError)

    /// Lists the installed add-ons in `order`, which names each of them once, on the account and so
    /// on every device. Add-ons are asked in this order, which orders streams, subtitles and catalogs.
    func setOrder(_ order: [ManifestURL]) async throws(AddonError)
}
