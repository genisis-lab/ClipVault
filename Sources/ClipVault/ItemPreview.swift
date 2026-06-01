import SwiftUI
import AppKit

/// A detail preview of a single history item, shown as a popover (Space bar or
/// the "Quick Look" context-menu action). Surfaces the full text of items that
/// are truncated in the list, and a larger view of images.
struct ItemPreview: View {
    let item: ClipboardItem
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
        }
        .padding(16)
        .frame(width: 420, height: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .foregroundStyle(.secondary)
            Text(kindLabel)
                .font(.headline)
            Spacer()
            if item.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let image = store.loadImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                missing("Image unavailable")
            }
        case .fileURLs:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileURLStrings, id: \.self) { s in
                        Text(URL(string: s)?.path ?? s)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .text, .richText:
            ScrollView {
                Text(item.text)
                    .font(.system(.body))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func missing(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .fileURLs: return "Files"
        }
    }
}

/// A compact reference of the popover's keyboard shortcuts.
struct ShortcutLegend: View {
    private let rows: [(String, String)] = [
        ("↑ / ↓", "Move selection"),
        ("↩", "Paste selected item"),
        ("⇧↩", "Paste as plain text"),
        ("⌘1…⌘9", "Paste the Nth item"),
        ("Space", "Quick Look preview"),
        ("⌘⌫", "Delete selected item")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .padding(.bottom, 2)
            ForEach(rows, id: \.0) { key, desc in
                HStack(spacing: 12) {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}
