import XCTest
import Carbon.HIToolbox
@testable import ClipVault

final class KeyComboTests: XCTestCase {

    func testDefaultIsOptionCommandV() {
        let combo = KeyCombo.default
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertTrue(combo.hasModifier)
        XCTAssertEqual(combo.displayString, "⌥⌘V")
    }

    func testModifierlessComboHasNoModifier() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0)
        XCTAssertFalse(combo.hasModifier)
    }

    func testDisplayStringOrdersModifiers() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                             carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘K")
    }

    func testSpotlightConflictDetected() {
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey))
        XCTAssertNotNil(combo.systemConflict)
    }

    func testQuitConflictDetected() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: UInt32(cmdKey))
        XCTAssertNotNil(combo.systemConflict)
    }

    func testScreenshotConflictDetected() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_4),
                             carbonModifiers: UInt32(cmdKey | shiftKey))
        XCTAssertNotNil(combo.systemConflict)
    }

    func testDefaultComboHasNoConflict() {
        XCTAssertNil(KeyCombo.default.systemConflict)
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 42, carbonModifiers: UInt32(cmdKey | optionKey))
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(combo, decoded)
    }
}
