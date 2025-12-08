import SwiftUI
import CryptoKit
import AppKit
import Carbon.HIToolbox
import Combine

// MARK: - Encryption Data Structures

struct EncryptedClipboardItem: Identifiable {
    let id: UUID
    let timestamp: Date
    let ciphertext: Data      // Encrypted text
    let nonce: Data           // AES.GCM.Nonce (12 bytes)
    let tag: Data             // Authentication tag (16 bytes)
}

enum EncryptionError: Error {
    case invalidInput
    case keyRetrievalFailed
    case encryptionFailed
    case decryptionFailed
    case corruptedData
}

// MARK: - Keychain Manager

class KeychainManager {
    private static let keyIdentifier = "com.airshiplabs.vaultclip.masterkey"

    enum KeychainError: Error {
        case storeFailed(OSStatus)
        case retrieveFailed(OSStatus)
        case deleteFailed(OSStatus)
    }

    static func getMasterKey() throws -> SymmetricKey {
        // Try to retrieve existing key
        if let existingKey = try? retrieveKey() {
            return existingKey
        }

        // Generate new key if none exists
        let newKey = SymmetricKey(size: .bits256)
        try storeKey(newKey)
        return newKey
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyIdentifier,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        // Zero the key data
        zeroMemory(keyData)

        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    private static func retrieveKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyIdentifier,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw KeychainError.retrieveFailed(status)
        }

        let key = SymmetricKey(data: keyData)

        // Zero the key data
        zeroMemory(keyData)

        return key
    }

    // For testing: delete key
    static func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyIdentifier
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Memory Protection

func zeroMemory(_ data: Data) {
    data.withUnsafeBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset_s(UnsafeMutableRawPointer(mutating: baseAddress),
                    ptr.count, 0, ptr.count)
        }
    }
}

func zeroMemory(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset_s(baseAddress, ptr.count, 0, ptr.count)
        }
    }
}

@main
struct VaultClipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
