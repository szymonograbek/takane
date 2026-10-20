/// An add-on in the user's profile.
struct InstalledAddon: Identifiable, Hashable, Sendable {
    let manifestURL: ManifestURL
    /// Names the add-on the user chose, which release logs keep private.
    let name: Redacted<String>
    let version: String
    /// False for add-ons the provider keeps installed, such as its official catalog.
    let isRemovable: Bool

    var id: ManifestURL { manifestURL }
}

enum AddonError: Error, Equatable, Sendable {
    /// The manifest could not be fetched or parsed.
    case manifestUnavailable(reason: String)
    case timedOut(stage: String)
    /// The provider refused the request outright.
    case rejected(reason: String)
}

/// Installs add-ons and reports which are installed.
protocol AddonService: Sendable {
    /// The installed add-ons now, then after every change.
    func installed() -> AsyncStream<[InstalledAddon]>

    /// Fetches the manifest and installs it. Installing an installed add-on returns it unchanged.
    func install(_ manifest: ManifestURL) async throws(AddonError) -> InstalledAddon

    /// Removing an add-on that is not installed does nothing.
    func uninstall(_ manifest: ManifestURL) async throws(AddonError)
}
