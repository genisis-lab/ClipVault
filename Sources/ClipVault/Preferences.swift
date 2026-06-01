import Foundation

/// Lightweight wrapper over UserDefaults for app preferences.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let maxItems = "maxItems"
        static let autoPaste = "autoPaste"
        static let launchAtLogin = "launchAtLogin"
        static let ignoreConcealed = "ignoreConcealed"
        static let pollInterval = "pollInterval"
        static let hotKey = "hotKey"
        static let maxTextLength = "maxTextLength"
        static let maxImagesBytes = "maxImagesBytes"
        static let hasShownWelcome = "hasShownWelcome"
    }

    init() {
        defaults.register(defaults: [
            Keys.maxItems: 200,
            Keys.autoPaste: true,
            Keys.launchAtLogin: false,
            Keys.ignoreConcealed: true,
            Keys.pollInterval: 0.4,
            // Cap a single text item at 1 MB of characters; longer captures are
            // truncated so history.json can't grow unbounded from one paste.
            Keys.maxTextLength: 1_000_000,
            // Total budget for stored image blobs (256 MB). Oldest unpinned
            // images are pruned first when exceeded.
            Keys.maxImagesBytes: 256 * 1024 * 1024
        ])
    }

    var maxItems: Int {
        get { defaults.integer(forKey: Keys.maxItems) }
        set { defaults.set(newValue, forKey: Keys.maxItems) }
    }

    /// When true, ClipVault synthesizes Cmd+V after putting an item on the pasteboard.
    var autoPaste: Bool {
        get { defaults.bool(forKey: Keys.autoPaste) }
        set { defaults.set(newValue, forKey: Keys.autoPaste) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// When true, clipboard entries marked concealed (e.g. password managers) are skipped.
    var ignoreConcealed: Bool {
        get { defaults.bool(forKey: Keys.ignoreConcealed) }
        set { defaults.set(newValue, forKey: Keys.ignoreConcealed) }
    }

    var pollInterval: Double {
        get { defaults.double(forKey: Keys.pollInterval) }
        set { defaults.set(newValue, forKey: Keys.pollInterval) }
    }

    /// The global hotkey used to toggle the popover. Persisted as JSON.
    var hotKey: KeyCombo {
        get {
            guard let data = defaults.data(forKey: Keys.hotKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .default
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    /// Maximum number of characters retained for a single text/rich-text item.
    var maxTextLength: Int {
        get { defaults.integer(forKey: Keys.maxTextLength) }
        set { defaults.set(newValue, forKey: Keys.maxTextLength) }
    }

    /// Maximum total bytes of image blobs kept on disk.
    var maxImagesBytes: Int {
        get { defaults.integer(forKey: Keys.maxImagesBytes) }
        set { defaults.set(newValue, forKey: Keys.maxImagesBytes) }
    }

    /// Whether the one-time welcome popover has been shown. Prevents the panel
    /// from auto-opening on every login.
    var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Keys.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Keys.hasShownWelcome) }
    }
}
