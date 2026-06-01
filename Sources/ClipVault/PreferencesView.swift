import SwiftUI

/// Preferences window content. Bindings write straight through to
/// `Preferences.shared` and trigger side effects (login item, store limits).
struct PreferencesView: View {
    @ObservedObject var store: HistoryStore

    var onHotKeyChange: () -> Void = {}
    var onPollIntervalChange: () -> Void = {}

    @State private var maxItems: Double
    @State private var autoPaste: Bool
    @State private var launchAtLogin: Bool
    @State private var ignoreConcealed: Bool
    @State private var accessibilityTrusted: Bool
    @State private var showClearConfirm = false
    @State private var hotKey: KeyCombo
    @State private var pollInterval: Double

    init(store: HistoryStore,
         onHotKeyChange: @escaping () -> Void = {},
         onPollIntervalChange: @escaping () -> Void = {}) {
        self.store = store
        self.onHotKeyChange = onHotKeyChange
        self.onPollIntervalChange = onPollIntervalChange
        _maxItems = State(initialValue: Double(Preferences.shared.maxItems))
        _autoPaste = State(initialValue: Preferences.shared.autoPaste)
        _launchAtLogin = State(initialValue: LoginItem.isEnabled())
        _ignoreConcealed = State(initialValue: Preferences.shared.ignoreConcealed)
        _accessibilityTrusted = State(initialValue: AccessibilityPermission.isTrusted())
        _hotKey = State(initialValue: Preferences.shared.hotKey)
        _pollInterval = State(initialValue: Preferences.shared.pollInterval)
    }

    var body: some View {
        Form {
            Section("History") {
                VStack(alignment: .leading) {
                    Text("Maximum items: \(Int(maxItems))")
                    Slider(value: $maxItems, in: 20...1000, step: 10) {
                        Text("Maximum items")
                    }
                    .onChange(of: maxItems) { _, newValue in
                        store.maxItems = Int(newValue)
                    }
                    Text("Pinned items are always kept and never counted against this limit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear History…", role: .destructive) {
                    showClearConfirm = true
                }
                .confirmationDialog("Clear clipboard history?",
                                    isPresented: $showClearConfirm) {
                    Button("Clear All (keep pinned)") { store.clearAll(keepPinned: true) }
                    Button("Clear Everything", role: .destructive) { store.clearAll(keepPinned: false) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
            }

            Section("Pasting") {
                Toggle("Paste automatically after selecting", isOn: $autoPaste)
                    .onChange(of: autoPaste) { _, newValue in
                        Preferences.shared.autoPaste = newValue
                        if newValue { refreshAccessibility() }
                    }
                if autoPaste && !accessibilityTrusted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Auto-paste needs Accessibility permission.")
                            .font(.caption)
                        Button("Grant…") {
                            AccessibilityPermission.requestIfNeeded()
                            AccessibilityPermission.openSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Privacy") {
                Toggle("Ignore passwords and concealed content", isOn: $ignoreConcealed)
                    .onChange(of: ignoreConcealed) { _, newValue in
                        Preferences.shared.ignoreConcealed = newValue
                    }
                Text("Items marked concealed by password managers are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LoginItem.setEnabled(newValue) {
                            launchAtLogin = LoginItem.isEnabled()
                        }
                    }
                LabeledContent("Global hotkey") {
                    HotKeyRecorderField(combo: $hotKey)
                        .frame(width: 200, height: 24)
                        .onChange(of: hotKey) { _, newValue in
                            Preferences.shared.hotKey = newValue
                            onHotKeyChange()
                        }
                }
                if let conflict = hotKey.systemConflict {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This shortcut may conflict with \(conflict).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Capture interval: \(String(format: "%.1f", pollInterval))s")
                    Slider(value: $pollInterval, in: 0.1...2.0, step: 0.1) {
                        Text("Capture interval")
                    }
                    .onChange(of: pollInterval) { _, newValue in
                        Preferences.shared.pollInterval = newValue
                        onPollIntervalChange()
                    }
                    Text("How often ClipVault checks the clipboard. Lower is more responsive; higher uses less CPU.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 440, minHeight: 560, idealHeight: 600)
        .onAppear { refreshAccessibility() }
    }

    private func refreshAccessibility() {
        accessibilityTrusted = AccessibilityPermission.isTrusted()
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }
}
