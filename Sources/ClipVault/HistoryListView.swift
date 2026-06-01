import SwiftUI
import AppKit

/// The main popover content: search field, type filter, and the scrollable
/// keyboard-navigable history list.
struct HistoryListView: View {
    @ObservedObject var store: HistoryStore
    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var kindFilter: ClipKind? = nil
    @State private var selectionIndex: Int = 0
    @State private var previewItem: ClipboardItem?
    @State private var showShortcutLegend: Bool = false
    @FocusState private var searchFocused: Bool

    /// Called when the user activates an item (Return / click).
    var onActivate: (ClipboardItem) -> Void
    /// Called to paste an item as plain text (Shift+Return / menu).
    var onActivatePlain: (ClipboardItem) -> Void
    var onOpenPreferences: () -> Void
    var onQuit: () -> Void

    private var results: [ClipboardItem] {
        store.filtered(query: debouncedQuery, kind: kindFilter)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 480)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, newValue in
            selectionIndex = 0
            searchTask?.cancel()
            // Empty query updates immediately; otherwise debounce ~150ms so we
            // don't re-scan the whole history on every keystroke.
            if newValue.isEmpty {
                debouncedQuery = ""
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = newValue
            }
        }
        .background(quickPasteKeys)
        .popover(item: $previewItem) { item in
            ItemPreview(item: item, store: store)
        }
    }

    /// Hidden buttons that map ⌘1…⌘9 to activating the Nth visible item.
    private var quickPasteKeys: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                Button("") { activateIndex(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .hidden()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                ClipSearchField(text: $query,
                                onMoveDown: { moveSelection(1) },
                                onMoveUp: { moveSelection(-1) },
                                onSubmit: activateSelection,
                                onSubmitPlain: activateSelectionPlain,
                                onDelete: deleteSelection,
                                onPreview: previewSelection)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            filterBar
        }
        .padding(10)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterChip(title: "All", kind: nil)
            filterChip(title: "Text", kind: .text)
            filterChip(title: "Rich", kind: .richText)
            filterChip(title: "Image", kind: .image)
            filterChip(title: "Files", kind: .fileURLs)
            Spacer()
        }
    }

    private func filterChip(title: String, kind: ClipKind?) -> some View {
        let isSelected = kindFilter == kind
        return Button {
            kindFilter = kind
            clampSelection()
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        HistoryRow(item: item,
                                   store: store,
                                   isSelected: index == selectionIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(item) }
                            .contextMenu { rowMenu(item) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectionIndex) { _, newValue in
                guard results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(results[newValue].id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ item: ClipboardItem) -> some View {
        Button("Quick Look") { previewItem = item }
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
        Button("Copy") { _ = PasteEngine.writeToPasteboard(item, store: store) }
        if item.kind == .richText {
            Button("Paste as Plain Text") { onActivatePlain(item) }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(results.count) item\(results.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { showShortcutLegend.toggle() } label: {
                Image(systemName: "questionmark.circle")
            }.buttonStyle(.plain).help("Keyboard shortcuts")
                .accessibilityLabel("Keyboard shortcuts")
                .popover(isPresented: $showShortcutLegend, arrowEdge: .bottom) {
                    ShortcutLegend()
                }
            Button { onOpenPreferences() } label: {
                Image(systemName: "gearshape")
            }.buttonStyle(.plain).help("Preferences")
                .accessibilityLabel("Preferences")
            Button { onQuit() } label: {
                Image(systemName: "power")
            }.buttonStyle(.plain).help("Quit ClipVault")
                .accessibilityLabel("Quit ClipVault")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectionIndex = min(max(0, selectionIndex + delta), results.count - 1)
    }

    private func clampSelection() {
        if results.isEmpty { selectionIndex = 0 }
        else { selectionIndex = min(selectionIndex, results.count - 1) }
    }

    private func activateSelection() {
        guard results.indices.contains(selectionIndex) else { return }
        onActivate(results[selectionIndex])
    }

    private func activateSelectionPlain() {
        guard results.indices.contains(selectionIndex) else { return }
        onActivatePlain(results[selectionIndex])
    }

    /// Show the detail preview for the current selection (Space bar).
    private func previewSelection() {
        guard results.indices.contains(selectionIndex) else { return }
        previewItem = results[selectionIndex]
    }

    /// Activate the item at a zero-based index (used by ⌘1…⌘9).
    private func activateIndex(_ index: Int) {
        guard results.indices.contains(index) else { return }
        onActivate(results[index])
    }

    private func deleteSelection() {
        guard results.indices.contains(selectionIndex) else { return }
        store.delete(results[selectionIndex])
        clampSelection()
    }
}
