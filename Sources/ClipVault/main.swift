import AppKit

// ClipVault runs as a menu-bar agent (LSUIElement); no Dock icon, no main menu
// window. We build the NSApplication manually so we can run as a SwiftPM
// executable wrapped into an .app bundle.
//
// main.swift executes on the main thread, so it is safe to assume MainActor
// isolation when constructing the (MainActor-isolated) app delegate.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Retain the delegate for the lifetime of the process.
    objc_setAssociatedObject(app, "clipVaultDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}
