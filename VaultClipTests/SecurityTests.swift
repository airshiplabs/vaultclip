import XCTest
import CryptoKit
@testable import VaultClip

class SecurityTests: XCTestCase {

    // CRITICAL TEST: Verify unique nonces per encryption
    func testEncryptionProducesUniqueNonces() throws {
        let encryption = ClipboardEncryption()
        let plaintext = "sensitive data"

        let encrypted1 = try encryption.encrypt(plaintext)
        let encrypted2 = try encryption.encrypt(plaintext)

        // Same plaintext MUST produce different ciphertext (unique nonces)
        XCTAssertNotEqual(encrypted1.ciphertext, encrypted2.ciphertext,
                         "Same plaintext should produce different ciphertext with unique nonces")
        XCTAssertNotEqual(encrypted1.nonce, encrypted2.nonce,
                         "Each encryption must use a unique nonce")
    }

    // CRITICAL TEST: Authenticated encryption detects tampering
    func testDecryptionFailsOnTamperedData() throws {
        let encryption = ClipboardEncryption()
        let plaintext = "sensitive data"

        let encrypted = try encryption.encrypt(plaintext)

        // Tamper with ciphertext (flip first byte)
        var tamperedCiphertext = encrypted.ciphertext
        tamperedCiphertext[0] ^= 0xFF

        // Create new struct with tampered data
        let tamperedItem = EncryptedClipboardItem(
            id: encrypted.id,
            timestamp: encrypted.timestamp,
            ciphertext: tamperedCiphertext,
            nonce: encrypted.nonce,
            tag: encrypted.tag
        )

        // Decryption MUST fail when data is tampered
        XCTAssertThrowsError(try encryption.decrypt(tamperedItem)) { error in
            XCTAssertTrue(error is CryptoKitError,
                         "Should throw CryptoKitError on tampered data")
        }
    }

    // Test roundtrip encryption/decryption
    func testEncryptionDecryptionRoundtrip() throws {
        let encryption = ClipboardEncryption()
        let plaintext = "test clipboard content"

        let encrypted = try encryption.encrypt(plaintext)
        let decrypted = try encryption.decrypt(encrypted)

        XCTAssertEqual(plaintext, decrypted,
                      "Decrypted text should match original plaintext")
    }

    // Test various input sizes
    func testEncryptionWithVariousInputSizes() throws {
        let encryption = ClipboardEncryption()

        let testCases = [
            "a",                                    // Single char
            String(repeating: "x", count: 100),     // Small
            String(repeating: "y", count: 10_000),  // Large
            "Unicode: 你好世界 🔐"                   // Unicode
        ]

        for plaintext in testCases {
            let encrypted = try encryption.encrypt(plaintext)
            let decrypted = try encryption.decrypt(encrypted)
            XCTAssertEqual(plaintext, decrypted,
                          "Failed for input: \(plaintext.prefix(20))...")
        }
    }

    // Test Keychain integration
    func testKeychainMasterKeyPersistence() throws {
        // Clean slate
        try? KeychainManager.deleteKey()

        // First retrieval (generates key)
        let key1 = try KeychainManager.getMasterKey()

        // Second retrieval (should be same key)
        let key2 = try KeychainManager.getMasterKey()

        // Keys should be identical
        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }

        XCTAssertEqual(data1, data2,
                      "Retrieved key should match stored key")

        // Cleanup
        try KeychainManager.deleteKey()
    }
}
