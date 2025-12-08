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

@main
struct VaultClipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
