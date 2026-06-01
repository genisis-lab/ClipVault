import Foundation
import AppKit
import Combine
import ImageIO

/// Owns the clipboard history: in-memory list, on-disk persistence, image
/// blobs, pruning, search, pin/delete operations.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let historyFileURL: URL
    private let imagesDirectory: URL

    /// In-memory cache of downscaled row thumbnails, keyed by image file name.
    /// Avoids re-decoding full-resolution PNGs from disk on every row render
    /// while scrolling an image-heavy list.
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private static let thumbnailMaxPixel: CGFloat = 72  // 36pt @2x

    /// Pending-save coalescing: rapid copies schedule a single debounced write
    /// instead of encoding + writing the whole history synchronously each time.
    private var saveTask: Task<Void, Never>?

    /// Maximum number of *unpinned* items retained. Pinned items are never pruned.
    var maxItems: Int {
        didSet {
            Preferences.shared.maxItems = maxItems
            prune()
            save()
        }
    }

    init(baseDirectory overrideBase: URL? = nil) {
        let base: URL
        if let overrideBase {
            base = overrideBase
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            base = appSupport.appendingPathComponent("ClipVault", isDirectory: true)
        }
        baseDirectory = base
        historyFileURL = base.appendingPathComponent("history.json")
        imagesDirectory = base.appendingPathComponent("images", isDirectory: true)
        maxItems = Preferences.shared.maxItems

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            items = decoded
        }
    }

    func save() {
        // Coalesce bursts of mutations (e.g. rapid copying) into one write.
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task { [weak self] in
            // Debounce: wait briefly; if another save arrives, this is cancelled.
            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
            guard !Task.isCancelled else { return }
            await self?.writeSnapshot(snapshot)
        }
    }

    /// Immediately encode and persist a snapshot. The encode + disk write run
    /// off the main actor so large histories don't hitch the UI.
    private func writeSnapshot(_ snapshot: [ClipboardItem]) async {
        let url = historyFileURL
        await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }

    /// Force a synchronous flush of any pending save. Call on shutdown so the
    /// latest state isn't lost if the debounce timer hasn't fired.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    // MARK: - Image blob helpers

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(name)
    }

    func loadImage(for item: ClipboardItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// A small cached thumbnail suitable for list rows. Decodes and downsamples
    /// the PNG once, then serves subsequent requests from memory.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let name = item.imageFileName else { return nil }
        let key = name as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let url = imagesDirectory.appendingPathComponent(name)
        guard let thumb = Self.makeThumbnail(from: url, maxPixel: Self.thumbnailMaxPixel) else {
            return nil
        }
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// Downsample an image file to fit within `maxPixel` on its longest side
    /// using ImageIO, which avoids fully decoding large images into memory.
    private static func makeThumbnail(from url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func writeImage(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    private func deleteImageFile(named name: String?) {
        guard let name else { return }
        thumbnailCache.removeObject(forKey: name as NSString)
        let url = imagesDirectory.appendingPathComponent(name)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Mutations

    /// Convert freshly captured content into a persisted item, writing any
    /// image bytes to the images directory first.
    func ingest(_ content: CapturedContent) {
        // De-dupe by fingerprint before doing any disk work.
        if let existingIndex = items.firstIndex(where: { $0.fingerprint == content.fingerprint }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
            sortItems()
            save()
            return
        }

        var imageFileName: String?
        if let data = content.imageData {
            imageFileName = writeImage(data)
        }

        // Cap very large text payloads so a single huge paste can't bloat
        // history.json. Truncation is marked so it's visible in previews.
        let maxLen = Preferences.shared.maxTextLength
        var text = content.text
        if maxLen > 0 && text.count > maxLen {
            text = String(text.prefix(maxLen)) + "… (truncated)"
        }

        let item = ClipboardItem(kind: content.kind,
                                 text: text,
                                 rtfData: content.rtfData,
                                 imageFileName: imageFileName,
                                 fileURLStrings: content.fileURLStrings,
                                 fingerprint: content.fingerprint)
        insert(item)
    }

    /// Insert a freshly captured item, de-duplicating against the most recent.
    func insert(_ item: ClipboardItem) {
        // If an identical item exists, move it to the top instead of duplicating.
        if let existingIndex = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
            // Re-sort so pinned items stay grouped at the top; without this a
            // reused unpinned item would jump above pinned ones.
            sortItems()
            save()
            return
        }

        items.insert(item, at: 0)
        sortItems()
        prune()
        save()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        // Keep pinned items visually grouped at the top, newest first within group.
        sortItems()
        save()
    }

    func delete(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteImageFile(named: items[idx].imageFileName)
        items.remove(at: idx)
        save()
    }

    func clearAll(keepPinned: Bool) {
        let removed: [ClipboardItem]
        if keepPinned {
            removed = items.filter { !$0.pinned }
            items = items.filter { $0.pinned }
        } else {
            removed = items
            items = []
        }
        removed.forEach { deleteImageFile(named: $0.imageFileName) }
        save()
    }

    // MARK: - Sorting & pruning

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func prune() {
        let unpinned = items.filter { !$0.pinned }
        if unpinned.count > maxItems {
            let toRemove = unpinned.suffix(unpinned.count - maxItems)
            for victim in toRemove {
                deleteImageFile(named: victim.imageFileName)
            }
            let removeIDs = Set(toRemove.map { $0.id })
            items.removeAll { removeIDs.contains($0.id) }
        }
        pruneImagesBySize()
    }

    /// Enforce a total on-disk budget for image blobs by removing the oldest
    /// unpinned images first. Pinned items are always kept.
    private func pruneImagesBySize() {
        let budget = Preferences.shared.maxImagesBytes
        guard budget > 0 else { return }

        // Gather image-bearing items with their file sizes.
        func fileSize(_ name: String?) -> Int {
            guard let name else { return 0 }
            let url = imagesDirectory.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize ?? 0
        }

        let imageItems = items.filter { $0.imageFileName != nil }
        var total = imageItems.reduce(0) { $0 + fileSize($1.imageFileName) }
        guard total > budget else { return }

        // Oldest unpinned images are the first to go (items are newest-first).
        let evictionOrder = imageItems
            .filter { !$0.pinned }
            .sorted { $0.createdAt < $1.createdAt }

        var evictIDs = Set<UUID>()
        for victim in evictionOrder {
            guard total > budget else { break }
            total -= fileSize(victim.imageFileName)
            deleteImageFile(named: victim.imageFileName)
            evictIDs.insert(victim.id)
        }
        if !evictIDs.isEmpty {
            items.removeAll { evictIDs.contains($0.id) }
        }
    }

    // MARK: - Search

    func filtered(query: String, kind: ClipKind?) -> [ClipboardItem] {
        items.filter { item in
            let matchesKind = kind == nil || item.kind == kind
            let matchesQuery = query.isEmpty ||
                item.text.localizedCaseInsensitiveContains(query) ||
                item.displayTitle.localizedCaseInsensitiveContains(query)
            return matchesKind && matchesQuery
        }
    }
}
