import SwiftUI

/// The user's own media servers, each opening its page, and adding a Jellyfin server or a WebDAV folder.
struct SourceSettings: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let sources = app.sources.state.sources
        SettingsPage(title: "Sources") {
            SettingsSymbol(name: "server.rack")
        } rows: {
            if !sources.isEmpty {
                SettingsSection {
                    ForEach(sources) { source in
                        NavigationLink {
                            SourceScreen(id: source.id)
                        } label: {
                            LabeledContent(source.name.text.rawValue, value: source.kind.name)
                        }
                        .accessibilityIdentifier("sources.row")
                    }
                }
            }
            SettingsSection(note: Self.note) {
                NavigationLink("Add Jellyfin Server") { SourceForm(.add(.jellyfin)) }
                    .accessibilityIdentifier("sources.addJellyfin")
                NavigationLink("Add WebDAV Folder") { SourceForm(.add(.webDAV)) }
                    .accessibilityIdentifier("sources.addWebDAV")
            }
        }
    }

    private static let note = "Play films and shows from your own Jellyfin server or WebDAV folder, next to your add-ons. "
        + "Their logins stay on this device."
}

/// One source: what it is, editing it and removing it. It goes back once the source is removed.
private struct SourceScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    let id: SourceID
    @State private var confirmingRemoval = false

    var body: some View {
        let state = app.sources.state
        let source = state.sources.first { $0.id == id }
        let name = source?.name.text.rawValue ?? "Source"
        SettingsPage(title: name) {
            SettingsSymbol(name: "server.rack")
        } rows: {
            if let source {
                SettingsSection {
                    ValueRow(title: "Name", value: name).accessibilityIdentifier("source.name")
                    ValueRow(title: "Kind", value: source.kind.name).accessibilityIdentifier("source.kind")
                    ValueRow(title: "Server", value: source.endpoint.description).accessibilityIdentifier("source.server")
                    ValueRow(title: "Username", value: source.username.name.rawValue).accessibilityIdentifier("source.username")
                }
                SettingsSection(note: removalFailure(state.removal)?.message) {
                    NavigationLink("Edit") { SourceForm(.edit(source)) }
                        .accessibilityIdentifier("source.edit")
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        if state.removal == .removing(id) { ProgressView() } else { Text("Remove") }
                    }
                    .accessibilityIdentifier("source.remove")
                }
            } else {
                // Shown for the moment before going back, so the screen keeps something to focus.
                ValueRow(title: "Source", value: "Removed")
            }
        }
        .confirmationDialog("Remove \(name)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove") { app.sources.send(.remove(id)) }
        } message: {
            Text("Its titles leave Home and Search. Nothing changes on the server.")
        }
        .onChange(of: source == nil) { _, removed in
            if removed { dismiss() }
        }
    }

    private func removalFailure(_ removal: SourcesFeature.Removal) -> SourceError? {
        if case .failed(let failed, let error) = removal, failed == id { error } else { nil }
    }
}

/// Adding a source by its server's address and a login, or renaming one and changing its address
/// or login. It goes back once the server accepted the login.
private struct SourceForm: View {
    enum Purpose {
        case add(SourceKind)
        case edit(MediaSource)
    }

    private enum Field: Hashable {
        case name, address, username, password, save
    }

    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let purpose: Purpose
    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @FocusState private var focus: Field?

    init(_ purpose: Purpose) {
        self.purpose = purpose
        switch purpose {
        case .add:
            _name = State(initialValue: "")
            _address = State(initialValue: "")
            _username = State(initialValue: "")
        case .edit(let source):
            _name = State(initialValue: source.name.text.rawValue)
            _address = State(initialValue: source.endpoint.description)
            _username = State(initialValue: source.username.name.rawValue)
        }
    }

    var body: some View {
        let save = app.sources.state.save
        ScrollView {
            VStack(spacing: Metrics.formSpacing) {
                ScreenTitle(title)
                Text(hint).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                if case .edit = purpose {
                    FormField(title: "Name") {
                        TextField("Name", text: $name)
                            .focused($focus, equals: .name)
                            .accessibilityIdentifier("sourceForm.name")
                    }
                }
                FormField(title: "Server Address") {
                    TextField(kind.addressExample, text: $address)
                        .textContentType(.URL)
                        .plainTextEntry()
                        .focused($focus, equals: .address)
                        .accessibilityIdentifier("sourceForm.url")
                }
                FormField(title: "Username") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .plainTextEntry()
                        .focused($focus, equals: .username)
                        .accessibilityIdentifier("sourceForm.username")
                }
                FormField(title: "Password") {
                    SecureField(isEditing ? "Leave empty to keep" : "Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .accessibilityIdentifier("sourceForm.password")
                }
                if let failure = failure(save) {
                    Text(failure.message)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("sourceForm.error")
                }
                // Enabled while saving, so focus stays on it. The feature ignores a second save.
                Button {
                    if let request { app.sources.send(request) }
                } label: {
                    if isSaving(save) { ProgressView() } else { Text("Save") }
                }
                .disabled(request == nil)
                .focused($focus, equals: .save)
                .accessibilityIdentifier("sourceForm.save")
            }
            .frame(maxWidth: Metrics.formWidth)
            .padding(Metrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .defaultFocus($focus, isEditing ? .name : .address)
        .screenTitle(title)
        .background(Palette.canvas.ignoresSafeArea())
        .onAppear { app.sources.send(.formOpened) }
        .onChange(of: save) { _, save in
            if case .saved = save, isMine(save) { dismiss() }
        }
    }

    /// What Save sends, once every field reads as what it holds.
    private var request: SourcesFeature.Event? {
        guard let endpoint = SourceEndpoint(address), let user = SourceUsername(username) else { return nil }
        switch purpose {
        case .add(let kind):
            guard let password = Password(password) else { return nil }
            return .add(kind, SourceLogin(endpoint: endpoint, username: user, password: password))
        case .edit(let source):
            guard let name = SourceName(name) else { return nil }
            let change = Password(password).map(PasswordChange.replace) ?? .keep
            return .update(source.id, SourceEdit(name: name, endpoint: endpoint, username: user, password: change))
        }
    }

    private var kind: SourceKind {
        switch purpose {
        case .add(let kind): kind
        case .edit(let source): source.kind
        }
    }

    private var isEditing: Bool {
        if case .edit = purpose { true } else { false }
    }

    private var title: String {
        switch purpose {
        case .add(.jellyfin): "Add Jellyfin Server"
        case .add(.webDAV): "Add WebDAV Folder"
        case .edit: "Edit Source"
        }
    }

    private var hint: String {
        switch kind {
        case .jellyfin: "Enter the address you open Jellyfin at and your Jellyfin login."
        case .webDAV: "Enter the folder's address and its login. Takane lists the videos in it and its subfolders."
        }
    }

    /// Whether a save answers this form: an add of its kind, or an edit of its source.
    private func isMine(_ save: SourcesFeature.Save) -> Bool {
        let target: SourcesFeature.SaveTarget
        switch save {
        case .idle: return false
        case .saving(let saving): target = saving
        case .failed(let failed, _): target = failed
        case .saved(let source):
            return switch purpose {
            case .add(let kind): source.kind == kind
            case .edit(let edited): source.id == edited.id
            }
        }
        return switch (purpose, target) {
        case (.add(let kind), .new(let newKind, _)): kind == newKind
        case (.edit(let source), .existing(let id)): source.id == id
        case (.add, .existing), (.edit, .new): false
        }
    }

    private func isSaving(_ save: SourcesFeature.Save) -> Bool {
        if case .saving = save { isMine(save) } else { false }
    }

    private func failure(_ save: SourcesFeature.Save) -> SourceError? {
        if case .failed(_, let error) = save, isMine(save) { error } else { nil }
    }
}

/// A form field with its name above it, since a filled field no longer shows its placeholder.
private struct FormField<Field: View>: View {
    let title: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text(title).font(.headline).foregroundStyle(Palette.secondary)
            field()
        }
    }
}

private extension View {
    /// Text typed as it is: addresses and usernames, not words.
    func plainTextEntry() -> some View {
        autocorrectionDisabled()
        #if os(tvOS)
            .textInputAutocapitalization(.never)
        #endif
    }
}

private extension SourceKind {
    var name: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .webDAV: "WebDAV"
        }
    }

    var addressExample: String {
        switch self {
        case .jellyfin: "http://192.168.1.10:8096"
        case .webDAV: "https://nas.local/dav/Movies"
        }
    }
}

private extension SourceEndpoint {
    /// The host, and the port when the address names one.
    var server: String {
        let url = url.rawValue
        let host = url.host(percentEncoded: false) ?? description
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

extension SourceError {
    /// Shown on the form or page where it happened.
    var message: String {
        switch self {
        case .unreachable: "The server didn't answer. Check the address, and that the server is on and on this network."
        case .badCredentials: "The username or password is incorrect."
        case .notJellyfin: "This address answers, but not as a Jellyfin server. Check the address and its port."
        case .notWebDAV: "This address answers, but not as a WebDAV folder. Check the address and its port."
        case .invalidResponse(let reason): "The server answered in a way Takane can't read (\(reason))."
        case .notFound: "This source was removed."
        case .storageFailed(let reason): "This device couldn't keep the login (\(reason))."
        }
    }
}
