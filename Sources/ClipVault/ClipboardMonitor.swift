import Foundation
import AppKit
import CryptoKit

/// Raw content captured from the pasteboard before it becomes a persisted item.
/// Image bytes are passed separately so the store can write them to disk and
/// assign a stable file name.
struct CapturedContent {
    var kind: ClipKind
    var text: String
    var rtfData: Data?
    var imageData: Data?
    var fileURLStrings: [String]
    var fingerprint: String
}

/// Polls `NSPasteboard.general` on a timer and reports newly captured content.
/// AppKit gives no change notification for the pasteboard, so timer polling
/// against `changeCount` is the standard approach.
@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onCapture: (CapturedContent) -> Void

    /// Types used by password managers / secure fields to opt out of history.
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// When ClipVault itself writes to the pasteboard (on paste-back), we bump
    /// this so the monitor ignores the change it just caused.
    private var suppressUntilChangeCount: Int = -1

    init(onCapture: @escaping (CapturedContent) -> Void) {
        self.onCapture = onCapture
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        stop()
        let interval = max(0.1, Preferences.shared.pollInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Tell the monitor to ignore any pasteboard changes up to and including
    /// `count`. Writing an item back can bump `changeCount` more than once
    /// (e.g. `clearContents()` plus one or more `setData` calls), so callers
    /// pass the actual change count observed right after writing.
    func suppressChanges(upTo count: Int) {
        suppressUntilChangeCount = max(suppressUntilChangeCount, count)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if current <= suppressUntilChangeCount { return }

        if Preferences.shared.ignoreConcealed {
            let types = pasteboard.types ?? []
            if types.contains(concealedType) || types.contains(transientType) {
                return
            }
        }

        // File URLs and text are cheap to read on the main thread. Images can
        // be large, so we read the raw bytes here but defer the decode/encode.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let strings = urls.map { $0.absoluteString }
            let fp = Self.fingerprint(Data(strings.joined(separator: "|").utf8))
            let display = urls.map { $0.path }.joined(separator: "\n")
            onCapture(CapturedContent(kind: .fileURLs, text: display, rtfData: nil,
                                      imageData: nil, fileURLStrings: strings, fingerprint: fp))
            return
        }

        if let raw = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            captureImageAsync(raw)
            return
        }

        if let rtf = pasteboard.data(forType: .rtf),
           let attr = try? NSAttributedString(data: rtf, options: [:], documentAttributes: nil) {
            let plain = attr.string
            // Fingerprint over the plain-text representation so the same visible
            // text copied from a plain field and a rich field de-duplicate.
            let fp = Self.fingerprint(Data(plain.utf8))
            onCapture(CapturedContent(kind: .richText, text: plain, rtfData: rtf,
                                      imageData: nil, fileURLStrings: [], fingerprint: fp))
            return
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let fp = Self.fingerprint(Data(string.utf8))
            onCapture(CapturedContent(kind: .text, text: string, rtfData: nil,
                                      imageData: nil, fileURLStrings: [], fingerprint: fp))
        }
    }

    /// Convert pasteboard image bytes (TIFF/PNG) to a normalized PNG off the
    /// main actor, then deliver the captured content back on the main actor.
    /// Keeps large-screenshot decoding from hitching the UI during polling.
    private func captureImageAsync(_ raw: Data) {
        Task { [weak self] in
            let converted: (png: Data, width: Int, height: Int)? = await Task.detached(priority: .utility) {
                guard let rep = NSBitmapImageRep(data: raw),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    return nil
                }
                return (png, rep.pixelsWide, rep.pixelsHigh)
            }.value

            guard let converted else { return }
            let fp = Self.fingerprint(converted.png)
            self?.onCapture(CapturedContent(kind: .image,
                                            text: "Image \(converted.width)×\(converted.height)",
                                            rtfData: nil, imageData: converted.png,
                                            fileURLStrings: [], fingerprint: fp))
        }
    }

    private static func fingerprint(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
