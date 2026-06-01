import SwiftUI
import AppKit

/// A single row in the history list, adapting its preview to the content kind.
struct HistoryRow: View {
    let item: ClipboardItem
    @ObservedObject var store: HistoryStore
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(2)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var accessibilityLabel: String {
        let kindLabel: String
        switch item.kind {
        case .text: kindLabel = "Text"
        case .richText: kindLabel = "Rich text"
        case .image: kindLabel = "Image"
        case .fileURLs: kindLabel = "Files"
        }
        let pin = item.pinned ? ", pinned" : ""
        return "\(kindLabel): \(item.displayTitle), \(relativeTime)\(pin)"
    }

    @ViewBuilder
    private var icon: some View {
        if item.kind == .image, let nsImage = store.thumbnail(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    /// Shared formatter — allocating a `RelativeDateTimeFormatter` per row
    /// render is wasteful while scrolling, so reuse a single instance.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}
