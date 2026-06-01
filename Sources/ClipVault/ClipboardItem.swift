import Foundation
import AppKit

/// The kind of content captured from the pasteboard.
enum ClipKind: String, Codable {
    case text
    case richText
    case image
    case fileURLs
}

/// A single captured clipboard entry. Persisted as Codable; large binary
/// payloads (images) are stored as separate files referenced by `imageFileName`.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipKind

    /// Plain-text representation used for display previews and search.
    var text: String

    /// RTF payload for rich text items (kept so we can paste back formatting).
    var rtfData: Data?

    /// File name (not full path) of an image stored in the images directory.
    var imageFileName: String?

    /// Absolute file URLs for `fileURLs` items.
    var fileURLStrings: [String]

    var createdAt: Date
    var pinned: Bool

    /// Content fingerprint used to de-duplicate consecutive identical copies.
    var fingerprint: String

    init(id: UUID = UUID(),
         kind: ClipKind,
         text: String,
         rtfData: Data? = nil,
         imageFileName: String? = nil,
         fileURLStrings: [String] = [],
         createdAt: Date = Date(),
         pinned: Bool = false,
         fingerprint: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtfData = rtfData
        self.imageFileName = imageFileName
        self.fileURLStrings = fileURLStrings
        self.createdAt = createdAt
        self.pinned = pinned
        self.fingerprint = fingerprint
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    /// A short single-line label for the list UI.
    var displayTitle: String {
        switch kind {
        case .text, .richText:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let collapsed = trimmed.replacingOccurrences(of: "\n", with: " ")
            return collapsed.isEmpty ? "(whitespace)" : collapsed
        case .image:
            return "Image"
        case .fileURLs:
            let names = fileURLStrings.compactMap { URL(string: $0)?.lastPathComponent }
            return names.isEmpty ? "Files" : names.joined(separator: ", ")
        }
    }

    var symbolName: String {
        switch kind {
        case .text: return "doc.plaintext"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .fileURLs: return "folder"
        }
    }
}
