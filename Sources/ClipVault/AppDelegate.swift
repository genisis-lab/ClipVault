import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var preferencesWindow: NSWindow?

    private let store = HistoryStore()
    private var monitor: ClipboardMonitor!
    private var hotKey: GlobalHotKey?

    /// The app that was frontmost before our popover opened, so we can paste
    /// back into it.
    private weak var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("ClipVault: applicationDidFinishLaunching")
        setupStatusItem()
        setupPopover()
        setupMonitor()
        setupHotKey()
        NSLog("ClipVault: setup complete, statusItem button=\(String(describing: statusItem.button)), visible=\(statusItem.isVisible)")

        // Give immediate visual feedback on first launch so the user can see
        // where ClipVault lives (the menu-bar icon can be hard to spot,
        // especially behind the notch). Only do this once — otherwise the
        // panel would pop on every login when "Launch at login" is enabled.
        if !Preferences.shared.hasShownWelcome {
            Preferences.shared.hasShownWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showPopover()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "ClipVault")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    /// The popover content's fixed size. Must match the `.frame` used in
    /// `HistoryListView` so the popover window is sized to fit exactly and
    /// never clips the header (search/filter bar) at the top.
    private static let popoverContentSize = NSSize(width: 380, height: 480)

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let root = HistoryListView(
            store: store,
            onActivate: { [weak self] item in self?.activate(item) },
            onActivatePlain: { [weak self] item in self?.activate(item, asPlainText: true) },
            onOpenPreferences: { [weak self] in self?.openPreferences() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: root)
        // Pin the hosting controller and popover to the exact content size.
        // Without this the popover sizes itself from the hosting controller's
        // first (pre-layout) fitting size, which can come back too small and
        // clip the top of the view.
        hosting.preferredContentSize = Self.popoverContentSize
        popover.contentSize = Self.popoverContentSize
        popover.contentViewController = hosting
    }

    private func setupMonitor() {
        monitor = ClipboardMonitor { [weak self] content in
            self?.store.ingest(content)
        }
        monitor.start()
    }

    private func setupHotKey() {
        let combo = Preferences.shared.hotKey
        hotKey = GlobalHotKey(keyCode: combo.keyCode,
                              modifiers: combo.carbonModifiers) { [weak self] in
            Task { @MainActor in self?.toggleViaHotKey() }
        }
    }

    /// Re-register the global hotkey from current preferences. Called when the
    /// user records a new shortcut in Preferences.
    func reloadHotKey() {
        hotKey = nil
        setupHotKey()
    }

    /// Restart the clipboard monitor so a changed poll interval takes effect.
    func reloadMonitor() {
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist any debounced changes that haven't been flushed yet.
        store.flush()
    }

    // MARK: - Popover control

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func toggleViaHotKey() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Capture the app that was frontmost right before we open, so auto-paste
        // can route back to it. Recompute every time (a stale value from launch
        // would send the paste to the wrong app), and never record ourselves.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        // Rebuild content so the search field re-focuses and list resets.
        setupPopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Activation (paste back)

    private func activate(_ item: ClipboardItem, asPlainText: Bool = false) {
        popover.performClose(nil)

        let wrote = PasteEngine.writeToPasteboard(item, store: store, asPlainText: asPlainText)
        // Suppress every pasteboard change our write produced (clearContents +
        // one or more setData calls can bump changeCount more than once).
        monitor.suppressChanges(upTo: NSPasteboard.general.changeCount)
        guard wrote else { return }

        // Move this item to the top so re-use bumps recency.
        store.insert(item)

        guard Preferences.shared.autoPaste else { return }

        // Reactivate the previous app, then synthesize Cmd+V.
        if let previousApp {
            previousApp.activate()
        }
        // Small delay so the target app regains focus before the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if AccessibilityPermission.isTrusted() {
                PasteEngine.synthesizePaste()
            }
        }
    }

    // MARK: - Preferences window

    private func openPreferences() {
        popover.performClose(nil)
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PreferencesView(
            store: store,
            onHotKeyChange: { [weak self] in self?.reloadHotKey() },
            onPollIntervalChange: { [weak self] in self?.reloadMonitor() }
        ))
        let window = NSWindow(contentViewController: hosting)
        window.title = "ClipVault Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 600))
        window.center()
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
