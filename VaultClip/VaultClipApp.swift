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
        var keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyIdentifier,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        // Zero the key data
        zeroMemory(&keyData)

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
              var keyData = result as? Data else {
            throw KeychainError.retrieveFailed(status)
        }

        let key = SymmetricKey(data: keyData)

        // Zero the key data
        zeroMemory(&keyData)

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

func zeroMemory(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset_s(baseAddress, ptr.count, 0, ptr.count)
        }
    }
}

// MARK: - Clipboard Encryption

class ClipboardEncryption {

    func encrypt(_ plaintext: String) throws -> EncryptedClipboardItem {
        // Validate input
        guard !plaintext.isEmpty else {
            throw EncryptionError.invalidInput
        }

        // Get master key from Keychain
        let key = try KeychainManager.getMasterKey()

        // Generate unique nonce (CRITICAL: never reuse)
        let nonce = AES.GCM.Nonce()

        // Convert string to Data
        guard let data = plaintext.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }

        // Encrypt with AES-256-GCM
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Extract components
        return EncryptedClipboardItem(
            id: UUID(),
            timestamp: Date(),
            ciphertext: sealedBox.ciphertext,
            nonce: Data(sealedBox.nonce),
            tag: sealedBox.tag
        )
    }

    func decrypt(_ item: EncryptedClipboardItem) throws -> String {
        // Get master key
        let key = try KeychainManager.getMasterKey()

        // Reconstruct nonce
        guard let nonce = try? AES.GCM.Nonce(data: item.nonce) else {
            throw EncryptionError.corruptedData
        }

        // Reconstruct sealed box
        guard let sealedBox = try? AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: item.ciphertext,
            tag: item.tag
        ) else {
            throw EncryptionError.corruptedData
        }

        // Decrypt and verify authentication tag
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        // Convert to string
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.corruptedData
        }

        // Zero the decrypted data
        defer {
            var mutableData = decryptedData
            zeroMemory(&mutableData)
        }

        return plaintext
    }
}

// MARK: - Clipboard Monitor

class ClipboardMonitor: ObservableObject {
    @Published var newClipboardText: String?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval = 0.5  // 500ms

    func startMonitoring() {
        // Initialize with current state
        lastChangeCount = pasteboard.changeCount

        // Poll for changes
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount

        // Only process if change count increased
        guard currentChangeCount > lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        // Extract plain text (safely)
        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else { return }

        // Validate input
        guard validateClipboardText(text) else { return }

        // Notify observers (will trigger encryption & storage)
        DispatchQueue.main.async {
            self.newClipboardText = text
        }
    }

    func validateClipboardText(_ text: String) -> Bool {
        // Basic validation
        guard text.count <= 1_000_000 else { return false }  // 1MB max
        guard text.utf16.count > 0 else { return false }     // Valid UTF-16
        return true
    }
}

// MARK: - Clipboard Store

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [EncryptedClipboardItem] = []

    private let maxItems = 100  // Limit for prototype
    private let encryption = ClipboardEncryption()

    func addClipboardText(_ plaintext: String) async {
        do {
            // Encrypt the text
            let encryptedItem = try encryption.encrypt(plaintext)

            // Add to history (newest first)
            items.insert(encryptedItem, at: 0)

            // Enforce limit
            if items.count > maxItems {
                items.removeLast()
            }

        } catch {
            // Safe to log errors (not content)
            print("Encryption failed: \(error)")
        }
    }

    func getDecryptedText(for item: EncryptedClipboardItem) -> String? {
        do {
            return try encryption.decrypt(item)
        } catch {
            print("Decryption failed: \(error)")
            return nil
        }
    }

    func pasteItem(_ item: EncryptedClipboardItem) {
        guard let plaintext = getDecryptedText(for: item) else { return }

        // Write to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plaintext, forType: .string)
    }

    func clearHistory() {
        items.removeAll()
    }
}

// MARK: - Hotkey Manager

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    typealias HotkeyCallback = () -> Void
    private var callback: HotkeyCallback?

    func register(
        key: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        callback: @escaping HotkeyCallback
    ) {
        self.callback = callback

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = UTGetOSTypeFromString("VCLP" as CFString)
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData!)
                    .takeUnretainedValue()
                manager.callback?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        RegisterEventHotKey(
            key,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

// MARK: - Window State

class WindowState: ObservableObject {
    @Published var isVisible = false

    func toggleVisibility() {
        isVisible.toggle()

        if isVisible {
            // Bring window to front
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - UI Components

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search clipboard...", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ClipboardItemRow: View {
    let item: EncryptedClipboardItem
    let store: ClipboardStore
    let isSelected: Bool

    @State private var preview: String = "Decrypting..."

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview)
                    .lineLimit(2)
                    .font(.body)

                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onAppear {
            loadPreview()
        }
    }

    private func loadPreview() {
        if let text = store.getDecryptedText(for: item) {
            // Show first 100 chars as preview
            preview = String(text.prefix(100))
        } else {
            preview = "[Decryption failed]"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var windowState: WindowState

    @State private var selectedItem: EncryptedClipboardItem?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText)
                .padding()

            // Clipboard history list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: selectedItem?.id == item.id
                        )
                        .onTapGesture {
                            handleSelection(item)
                        }
                    }
                }
                .padding()
            }

            // Footer with stats
            HStack {
                Text("\(store.items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear All") {
                    store.clearHistory()
                }
                .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var filteredItems: [EncryptedClipboardItem] {
        // For v0.1, return all items (search not implemented)
        store.items
    }

    private func handleSelection(_ item: EncryptedClipboardItem) {
        store.pasteItem(item)
        windowState.isVisible = false
    }
}

// MARK: - Main App

// Wrapper to hold cancellables
class AppCoordinator {
    var cancellables = Set<AnyCancellable>()
}

@main
struct VaultClipApp: App {
    @StateObject private var clipboardMonitor = ClipboardMonitor()
    @StateObject private var clipboardStore = ClipboardStore()
    @StateObject private var windowState = WindowState()

    private let hotkeyManager = HotkeyManager()
    private let coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: clipboardStore,
                windowState: windowState
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
    }

    init() {
        setupClipboardPipeline()
        setupHotkey()
        startMonitoring()
    }

    private func setupClipboardPipeline() {
        // Wire monitor to store
        clipboardMonitor.$newClipboardText
            .compactMap { $0 }
            .sink { [clipboardStore] text in
                Task {
                    await clipboardStore.addClipboardText(text)
                }
            }
            .store(in: &coordinator.cancellables)
    }

    private func setupHotkey() {
        hotkeyManager.register { [windowState] in
            DispatchQueue.main.async {
                windowState.toggleVisibility()
            }
        }
    }

    private func startMonitoring() {
        clipboardMonitor.startMonitoring()
    }
}
