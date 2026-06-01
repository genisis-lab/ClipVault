# ClipVault

A complete native macOS clipboard history manager. Lives in your menu bar,
remembers everything you copy, and pastes it back with a keystroke.

## Features

- **Background capture** of text, rich text (RTF), images, and file URLs
- **Persistent history** stored in `~/Library/Application Support/ClipVault`
  (survives restarts; images saved as PNG blobs)
- **Search** and **type filtering** (All / Text / Rich / Image / Files)
- **Pin/favorite** items — pinned items are never pruned
- **Menu-bar popover** with full keyboard navigation:
  - `↑` / `↓` — move selection
  - `↩` — paste selected item
  - `⇧↩` — paste selected item as plain text (strips formatting)
  - `⌘1`…`⌘9` — paste the Nth visible item
  - `Space` — Quick Look preview of the selected item (full text / large image)
  - `⌘⌫` — delete selected item
  - A `?` button in the footer shows the full shortcut legend
- **Configurable global hotkey** (defaults to `⌥⌘V`) to toggle the panel from
  anywhere — record your own in Preferences
- **Auto-paste**: writes the item to the pasteboard and synthesizes `⌘V` into
  the previously active app (requires Accessibility permission)
- **Privacy**: skips content marked concealed/transient by password managers
- **Preferences**: max history size, capture interval, custom hotkey, launch at
  login, auto-paste toggle, ignore-concealed toggle, and clear history
  (keep-pinned or everything)
- **Storage guards**: long text is truncated and total image storage is capped
  so history can't grow without bound

## Build & run

```bash
swift build              # debug build
swift run                # run from the command line
swift test               # run the unit test suite
./build-app.sh           # produce dist/ClipVault.app (release, bundled, signed)
open dist/ClipVault.app  # launch the bundled app
./notarize.sh            # (optional) sign with Developer ID, notarize & staple
```

CI runs `swift build`, `swift test`, and the bundle assembly on every push via
GitHub Actions (`.github/workflows/ci.yml`).

Requires macOS 14+ and a Swift 5.9+ toolchain (Xcode 15+).

## Permissions

- **No permission needed** for capturing history or the global hotkey.
- **Accessibility** permission is only required for auto-paste (synthesizing
  `⌘V`). ClipVault prompts for it from Preferences when you enable auto-paste.
  Without it, items are still copied to the clipboard — you just press `⌘V`
  yourself.

## Architecture

| File | Responsibility |
|------|----------------|
| `main.swift` | Entry point; runs as an `.accessory` (menu-bar) app |
| `AppDelegate.swift` | Wires status item, popover, monitor, hotkey, paste-back |
| `ClipboardMonitor.swift` | Polls `NSPasteboard` `changeCount`, captures content |
| `HistoryStore.swift` | In-memory list, JSON + image persistence, prune/search |
| `ClipboardItem.swift` | The persisted model |
| `PasteEngine.swift` | Writes items to the pasteboard, synthesizes `⌘V` |
| `GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper |
| `KeyCombo.swift` | Hotkey model + key-code/glyph translation |
| `HotKeyRecorderField.swift` | AppKit shortcut recorder used in Preferences |
| `SystemServices.swift` | Launch-at-login (SMAppService) + Accessibility checks |
| `Preferences.swift` | `UserDefaults`-backed settings |
| `HistoryListView.swift` / `HistoryRow.swift` / `ClipSearchField.swift` | Popover UI |
| `ItemPreview.swift` | Quick Look detail preview + keyboard shortcut legend |
| `PreferencesView.swift` | Settings window |

The clipboard has no change notification on macOS, so ClipVault polls
`changeCount` on a short timer (default 0.4s) — the standard approach used by
every clipboard manager.

## License

ClipVault is released under the [MIT License](LICENSE).
