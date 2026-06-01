import XCTest
@testable import ClipVault

@MainActor
final class HistoryStoreTests: XCTestCase {

    /// A throwaway store rooted in a unique temp directory so tests never touch
    /// the user's real history.
    private func makeStore() -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVaultTests-\(UUID().uuidString)", isDirectory: true)
        return (HistoryStore(baseDirectory: dir), dir)
    }

    private func textContent(_ s: String, fingerprint: String? = nil) -> CapturedContent {
        CapturedContent(kind: .text, text: s, rtfData: nil, imageData: nil,
                        fileURLStrings: [], fingerprint: fingerprint ?? s)
    }

    override func tearDown() {
        // Reset any preferences the tests mutated.
        Preferences.shared.maxTextLength = 1_000_000
        super.tearDown()
    }

    func testIngestAddsItemNewestFirst() {
        let (store, _) = makeStore()
        store.ingest(textContent("first"))
        store.ingest(textContent("second"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.text, "second")
    }

    func testDuplicateMovesToTopWithoutGrowing() {
        let (store, _) = makeStore()
        store.ingest(textContent("a", fingerprint: "fp-a"))
        store.ingest(textContent("b", fingerprint: "fp-b"))
        store.ingest(textContent("a", fingerprint: "fp-a")) // re-copy "a"
        XCTAssertEqual(store.items.count, 2, "duplicate should not create a new entry")
        XCTAssertEqual(store.items.first?.text, "a", "re-copied item should bubble to the top")
    }

    func testPinnedItemsStayAboveUnpinnedAfterReuse() {
        let (store, _) = makeStore()
        store.ingest(textContent("pinned", fingerprint: "fp-p"))
        let pinned = store.items[0]
        store.togglePin(pinned)
        store.ingest(textContent("fresh", fingerprint: "fp-f"))

        // Re-copy the unpinned "fresh" item; it must not jump above the pinned one.
        store.insert(store.items.first(where: { $0.text == "fresh" })!)
        XCTAssertTrue(store.items[0].pinned, "pinned item must remain at the top")
        XCTAssertEqual(store.items[0].text, "pinned")
    }

    func testCountPruningKeepsMostRecentUnpinned() {
        let (store, _) = makeStore()
        store.maxItems = 3
        for i in 0..<6 {
            store.ingest(textContent("item-\(i)", fingerprint: "fp-\(i)"))
        }
        XCTAssertEqual(store.items.count, 3)
        // Newest three (3,4,5) survive; oldest are pruned.
        XCTAssertEqual(store.items.map(\.text), ["item-5", "item-4", "item-3"])
    }

    func testPinnedItemsAreNotCounted() {
        let (store, _) = makeStore()
        store.maxItems = 2
        store.ingest(textContent("keep-me", fingerprint: "fp-keep"))
        store.togglePin(store.items[0])
        for i in 0..<5 {
            store.ingest(textContent("x-\(i)", fingerprint: "fp-x-\(i)"))
        }
        // 2 unpinned + 1 pinned retained.
        XCTAssertEqual(store.items.filter { $0.pinned }.count, 1)
        XCTAssertEqual(store.items.filter { !$0.pinned }.count, 2)
        XCTAssertTrue(store.items.contains { $0.text == "keep-me" })
    }

    func testLongTextIsTruncatedOnIngest() {
        let (store, _) = makeStore()
        Preferences.shared.maxTextLength = 100
        let long = String(repeating: "z", count: 500)
        store.ingest(textContent(long, fingerprint: "fp-long"))
        let stored = store.items[0].text
        XCTAssertTrue(stored.hasSuffix("… (truncated)"))
        XCTAssertLessThan(stored.count, 200)
    }

    func testDeleteRemovesItem() {
        let (store, _) = makeStore()
        store.ingest(textContent("doomed", fingerprint: "fp-d"))
        store.delete(store.items[0])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testClearAllKeepPinned() {
        let (store, _) = makeStore()
        store.ingest(textContent("pinned", fingerprint: "fp-p"))
        store.togglePin(store.items[0])
        store.ingest(textContent("temp", fingerprint: "fp-t"))
        store.clearAll(keepPinned: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "pinned")
    }

    func testFilterByQueryAndKind() {
        let (store, _) = makeStore()
        store.ingest(textContent("hello world", fingerprint: "fp-1"))
        store.ingest(textContent("goodbye", fingerprint: "fp-2"))
        XCTAssertEqual(store.filtered(query: "hello", kind: nil).count, 1)
        XCTAssertEqual(store.filtered(query: "", kind: .image).count, 0)
        XCTAssertEqual(store.filtered(query: "", kind: .text).count, 2)
    }

    func testPersistenceRoundTripsViaFlush() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVaultTests-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(baseDirectory: dir)
        store.ingest(textContent("persist me", fingerprint: "fp-persist"))
        store.flush()  // synchronous write

        // A fresh store over the same directory should load the saved item.
        let reloaded = HistoryStore(baseDirectory: dir)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.text, "persist me")
    }
}
