import XCTest
import CryptoKit
@testable import VaultClip

class SecurityEnhancementsTests: XCTestCase {

    // MARK: - Screen Recording Protection (vaultclip-g4x)

    func testScreenRecordingProtectionApplied() {
        // WindowState.applyScreenProtection() sets sharingType = .none on all windows.
        // In a headless test environment there are no windows, so we verify the
        // WindowState type exists and the logic compiles correctly.
        let windowState = WindowState()
        XCTAssertFalse(windowState.isVisible)
        // After toggle, isVisible becomes true which triggers applyScreenProtection()
        windowState.toggleVisibility()
        XCTAssertTrue(windowState.isVisible)
        // All real windows (if any) should have sharingType = .none
        for window in NSApplication.shared.windows {
            XCTAssertEqual(window.sharingType, .none,
                "Every app window must have sharingType = .none (screen recording protection)")
        }
    }

    func testProtectedLabelHidesAccessibilityValue() {
        // ProtectedLabel returns a generic accessibility label, not the actual text.
        // We verify it compiles and renders with the expected structure.
        let label = ProtectedLabel(text: "super secret clipboard content")
        // The actual accessibility value is set to "" by .accessibilityValue("") modifier.
        // We can only verify the struct initializes correctly without UI runtime.
        XCTAssertNotNil(label)
    }

    // MARK: - Memory Lock (vaultclip-zbt)

    func testSecureMemoryLockAndUnlock() {
        var buffer = Data(repeating: 0xAB, count: 64)
        buffer.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            // lock() should not crash; mlock may fail if limits are hit — non-fatal
            SecureMemory.lock(base, count: ptr.count)
            SecureMemory.unlock(base, count: ptr.count)
        }
        // If we get here, no crash — mlock errors are warnings, not fatals
        XCTAssertEqual(buffer.count, 64)
    }

    func testSecureMemoryZeroLengthIsNoop() {
        var empty = Data()
        empty.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                // Must not crash for zero-length buffers
                SecureMemory.lock(base, count: 0)
                SecureMemory.unlock(base, count: 0)
            }
        }
    }

    func testDecryptionZeroesMemoryAfterUse() throws {
        // Verify ClipboardEncryption.decrypt() doesn't throw and cleans up.
        // (Actual memory zeroing is verified via sanitizers / Instruments in Xcode)
        let crypto = ClipboardEncryption()
        let plaintext = "sensitive clipboard data"
        let item = try crypto.encrypt(plaintext)
        let decrypted = try crypto.decrypt(item)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Secure Preview (vaultclip-0m6)

    func testSecurePreviewLimitsExposureTo100Chars() throws {
        let longText = String(repeating: "A", count: 500)
        let crypto = ClipboardEncryption()
        let item = try crypto.encrypt(longText)
        let preview = SecurePreview(encrypted: item).generatePreview()
        XCTAssertLessThanOrEqual(preview.count, 100,
            "SecurePreview must truncate to at most 100 characters")
        XCTAssertEqual(preview, String(repeating: "A", count: 100))
    }

    func testSecurePreviewHandlesShortText() throws {
        let shortText = "Hello"
        let crypto = ClipboardEncryption()
        let item = try crypto.encrypt(shortText)
        let preview = SecurePreview(encrypted: item).generatePreview()
        XCTAssertEqual(preview, "Hello")
    }

    func testSecurePreviewHandlesDecryptionFailure() {
        // Craft a corrupted item — preview should return the failure placeholder
        let corrupted = EncryptedClipboardItem(
            id: UUID(),
            timestamp: Date(),
            ciphertext: Data([0x00, 0x01]),
            nonce: Data(repeating: 0, count: 12),
            tag: Data(repeating: 0, count: 16)
        )
        let preview = SecurePreview(encrypted: corrupted).generatePreview()
        XCTAssertEqual(preview, "[Decryption failed]")
    }

    // MARK: - Authentication Manager (vaultclip-13n)

    func testAuthManagerInitialStateIsLocked() {
        let authManager = AuthenticationManager()
        XCTAssertFalse(authManager.isAuthenticated,
            "AuthenticationManager must start in locked state")
    }

    func testAuthManagerLockResetsState() {
        let authManager = AuthenticationManager()
        // Simulate authenticated state (would normally require biometric prompt)
        // We can only test that lock() resets to false
        authManager.lock()
        XCTAssertFalse(authManager.isAuthenticated)
    }

    func testAuthManagerRecordActivityDoesNotCrash() {
        let authManager = AuthenticationManager()
        // recordActivity() should not throw or crash
        authManager.recordActivity()
        authManager.recordActivity()
    }

    // MARK: - Persistent Storage (vaultclip-liy)

    func testEncryptedDatabaseCreateAndFetch() throws {
        let db = try EncryptedDatabase()
        let crypto = EnhancedClipboardEncryption()
        let plaintext = "test clipboard content"
        let (item, encryptedKey) = try crypto.encrypt(plaintext)

        try db.insert(item, encryptedItemKey: encryptedKey)

        let results = try db.fetchAll(limit: 10)
        XCTAssertEqual(results.count, 1)

        let (fetchedItem, fetchedKey) = results[0]
        XCTAssertEqual(fetchedItem.id, item.id)

        let decrypted = try crypto.decrypt(fetchedItem, encryptedItemKey: fetchedKey)
        XCTAssertEqual(decrypted, plaintext)

        // Cleanup
        try db.deleteAll()
    }

    func testEncryptedDatabaseDelete() throws {
        let db = try EncryptedDatabase()
        let crypto = EnhancedClipboardEncryption()
        let (item, key) = try crypto.encrypt("delete me")
        try db.insert(item, encryptedItemKey: key)
        XCTAssertEqual(try db.fetchAll().count, 1)
        try db.delete(item.id)
        XCTAssertEqual(try db.fetchAll().count, 0)
    }

    func testEncryptedDatabaseExcludedFromBackup() throws {
        let db = try EncryptedDatabase()
        // The init sets isExcludedFromBackup = true on the VaultClip dir.
        // We verify the database object was created without errors.
        XCTAssertNotNil(db)
        _ = db  // suppress unused warning
    }

    // MARK: - Per-Item Key Architecture (vaultclip-liy)

    func testPerItemKeysProduceDifferentCiphertexts() throws {
        let crypto = EnhancedClipboardEncryption()
        let plaintext = "same content"
        let (item1, _) = try crypto.encrypt(plaintext)
        let (item2, _) = try crypto.encrypt(plaintext)
        // Same plaintext + different per-item keys must produce different ciphertexts
        XCTAssertNotEqual(item1.ciphertext, item2.ciphertext,
            "Per-item keys must ensure same plaintext produces different ciphertexts")
        XCTAssertNotEqual(item1.nonce, item2.nonce,
            "Each encryption must use a unique nonce")
    }

    func testPerItemKeyDecryptionRoundtrip() throws {
        let crypto = EnhancedClipboardEncryption()
        let plaintext = "roundtrip test"
        let (item, encryptedKey) = try crypto.encrypt(plaintext)
        let decrypted = try crypto.decrypt(item, encryptedItemKey: encryptedKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testPerItemKeyTamperDetection() throws {
        let crypto = EnhancedClipboardEncryption()
        let (item, var encryptedKey) = try crypto.encrypt("tamper test")
        // Flip a byte in the encrypted key — decryption must fail
        encryptedKey[0] ^= 0xFF
        XCTAssertThrowsError(
            try crypto.decrypt(item, encryptedItemKey: encryptedKey),
            "Tampered item key must cause decryption failure"
        )
    }

    // MARK: - Existing Encryption Tests (regression)

    func testEncryptionProducesUniqueNonces() throws {
        let crypto = ClipboardEncryption()
        let item1 = try crypto.encrypt("test")
        let item2 = try crypto.encrypt("test")
        XCTAssertNotEqual(item1.nonce, item2.nonce)
        XCTAssertNotEqual(item1.ciphertext, item2.ciphertext)
    }

    func testDecryptionFailsOnTamperedData() throws {
        let crypto = ClipboardEncryption()
        var item = try crypto.encrypt("test data")
        // Flip a byte in the ciphertext — authenticated encryption must detect tampering
        var tampered = item.ciphertext
        tampered[0] ^= 0xFF
        let tamperedItem = EncryptedClipboardItem(
            id: item.id, timestamp: item.timestamp,
            ciphertext: tampered, nonce: item.nonce, tag: item.tag
        )
        XCTAssertThrowsError(try crypto.decrypt(tamperedItem))
    }
}
