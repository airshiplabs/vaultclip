import SwiftUI
import CryptoKit
import AppKit
import Carbon.HIToolbox
import Combine
import LocalAuthentication
import SQLite3

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
        if let existingKey = try? retrieveKey() {
            return existingKey
        }
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
        zeroMemory(&keyData)
        return key
    }

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

// MARK: - Secure Memory (vaultclip-zbt: mlock/munlock for swap prevention)

class SecureMemory {
    /// Lock memory pages to prevent swap. Non-fatal on failure.
    static func lock(_ pointer: UnsafeRawPointer, count: Int) {
        guard count > 0 else { return }
        if mlock(pointer, count) != 0 {
            print("SecureMemory: mlock warning (errno \(errno)) — swap protection unavailable for this buffer")
        }
    }

    static func unlock(_ pointer: UnsafeRawPointer, count: Int) {
        guard count > 0 else { return }
        if munlock(pointer, count) != 0 {
            print("SecureMemory: munlock warning (errno \(errno))")
        }
    }
}

// MARK: - Clipboard Encryption (with mlock)

class ClipboardEncryption {

    func encrypt(_ plaintext: String) throws -> EncryptedClipboardItem {
        guard !plaintext.isEmpty else { throw EncryptionError.invalidInput }
        let key = try KeychainManager.getMasterKey()
        let nonce = AES.GCM.Nonce()
        guard let data = plaintext.data(using: .utf8) else { throw EncryptionError.invalidInput }
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        return EncryptedClipboardItem(
            id: UUID(),
            timestamp: Date(),
            ciphertext: sealedBox.ciphertext,
            nonce: Data(sealedBox.nonce),
            tag: sealedBox.tag
        )
    }

    func decrypt(_ item: EncryptedClipboardItem) throws -> String {
        let key = try KeychainManager.getMasterKey()
        guard let nonce = try? AES.GCM.Nonce(data: item.nonce) else {
            throw EncryptionError.corruptedData
        }
        guard let sealedBox = try? AES.GCM.SealedBox(
            nonce: nonce, ciphertext: item.ciphertext, tag: item.tag
        ) else {
            throw EncryptionError.corruptedData
        }
        var decryptedData = try AES.GCM.open(sealedBox, using: key)

        // Lock memory to prevent swap (vaultclip-zbt)
        decryptedData.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress { SecureMemory.lock(base, count: ptr.count) }
        }
        defer {
            decryptedData.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    memset_s(base, ptr.count, 0, ptr.count)
                    SecureMemory.unlock(base, count: ptr.count)
                }
            }
        }
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.corruptedData
        }
        return plaintext
    }
}

// MARK: - Secure Preview (vaultclip-0m6: minimize decrypted memory lifetime)

struct SecurePreview {
    private let encrypted: EncryptedClipboardItem
    private let maxPreviewLength: Int = 100

    init(encrypted: EncryptedClipboardItem) {
        self.encrypted = encrypted
    }

    /// Decrypt on-demand and return a truncated preview. Full plaintext is immediately discarded.
    func generatePreview() -> String {
        guard let decrypted = try? ClipboardEncryption().decrypt(encrypted) else {
            return "[Decryption failed]"
        }
        return String(decrypted.prefix(maxPreviewLength))
    }
}

// MARK: - Enhanced Clipboard Encryption (vaultclip-liy: per-item keys)

class EnhancedClipboardEncryption {

    func encrypt(_ plaintext: String) throws -> (item: EncryptedClipboardItem, encryptedItemKey: Data) {
        guard !plaintext.isEmpty else { throw EncryptionError.invalidInput }

        let itemKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        guard let data = plaintext.data(using: .utf8) else { throw EncryptionError.invalidInput }
        let sealedBox = try AES.GCM.seal(data, using: itemKey, nonce: nonce)

        let masterKey = try KeychainManager.getMasterKey()
        var itemKeyData = itemKey.withUnsafeBytes { Data($0) }
        let itemKeyNonce = AES.GCM.Nonce()
        let encryptedKey = try AES.GCM.seal(itemKeyData, using: masterKey, nonce: itemKeyNonce)
        zeroMemory(&itemKeyData)

        let item = EncryptedClipboardItem(
            id: UUID(),
            timestamp: Date(),
            ciphertext: sealedBox.ciphertext,
            nonce: Data(sealedBox.nonce),
            tag: sealedBox.tag
        )
        guard let encryptedKeyData = encryptedKey.combined else {
            throw EncryptionError.encryptionFailed
        }
        return (item, encryptedKeyData)
    }

    func decrypt(_ item: EncryptedClipboardItem, encryptedItemKey: Data) throws -> String {
        let masterKey = try KeychainManager.getMasterKey()
        let encryptedKeySealedBox = try AES.GCM.SealedBox(combined: encryptedItemKey)
        var itemKeyData = try AES.GCM.open(encryptedKeySealedBox, using: masterKey)
        let itemKey = SymmetricKey(data: itemKeyData)
        zeroMemory(&itemKeyData)

        guard let nonce = try? AES.GCM.Nonce(data: item.nonce) else {
            throw EncryptionError.corruptedData
        }
        guard let sealedBox = try? AES.GCM.SealedBox(
            nonce: nonce, ciphertext: item.ciphertext, tag: item.tag
        ) else {
            throw EncryptionError.corruptedData
        }
        var decryptedData = try AES.GCM.open(sealedBox, using: itemKey)

        decryptedData.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress { SecureMemory.lock(base, count: ptr.count) }
        }
        defer {
            decryptedData.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    memset_s(base, ptr.count, 0, ptr.count)
                    SecureMemory.unlock(base, count: ptr.count)
                }
            }
        }
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.corruptedData
        }
        return plaintext
    }
}

// MARK: - Encrypted SQLite Database (vaultclip-liy)

enum DatabaseError: Error {
    case openFailed
    case createSchemaFailed
    case insertFailed
    case queryFailed
    case deleteFailed
}

class EncryptedDatabase {
    private let dbPath: URL
    private var db: OpaquePointer?

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        var vaultClipDir = appSupport.appendingPathComponent("VaultClip")
        try FileManager.default.createDirectory(at: vaultClipDir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try vaultClipDir.setResourceValues(resourceValues)
        dbPath = vaultClipDir.appendingPathComponent("clipboard.db")
        try openDatabase()
        try createSchema()
    }

    private func openDatabase() throws {
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw DatabaseError.openFailed
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            ciphertext BLOB NOT NULL,
            nonce BLOB NOT NULL,
            tag BLOB NOT NULL,
            item_key_encrypted BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_items(timestamp DESC);
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errPtr) == SQLITE_OK else {
            sqlite3_free(errPtr)
            throw DatabaseError.createSchemaFailed
        }
    }

    func insert(_ item: EncryptedClipboardItem, encryptedItemKey: Data) throws {
        let sql = """
        INSERT OR REPLACE INTO clipboard_items
            (id, timestamp, ciphertext, nonce, tag, item_key_encrypted)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.insertFailed
        }
        defer { sqlite3_finalize(stmt) }
        let idStr = item.id.uuidString
        sqlite3_bind_text(stmt, 1, idStr, -1, nil)
        sqlite3_bind_int64(stmt, 2, Int64(item.timestamp.timeIntervalSince1970))
        item.ciphertext.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(ptr.count), nil)
        }
        item.nonce.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(ptr.count), nil)
        }
        item.tag.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 5, ptr.baseAddress, Int32(ptr.count), nil)
        }
        encryptedItemKey.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(ptr.count), nil)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed
        }
    }

    func fetchAll(limit: Int = 100) throws -> [(EncryptedClipboardItem, Data)] {
        let sql = """
        SELECT id, timestamp, ciphertext, nonce, tag, item_key_encrypted
        FROM clipboard_items ORDER BY timestamp DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [(EncryptedClipboardItem, Data)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idCStr)) else { continue }
            let ts = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
            func blob(at col: Int32) -> Data {
                guard let ptr = sqlite3_column_blob(stmt, col) else { return Data() }
                return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, col)))
            }
            let item = EncryptedClipboardItem(
                id: id, timestamp: ts,
                ciphertext: blob(at: 2), nonce: blob(at: 3), tag: blob(at: 4)
            )
            results.append((item, blob(at: 5)))
        }
        return results
    }

    func delete(_ id: UUID) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.deleteFailed
        }
        defer { sqlite3_finalize(stmt) }
        let idStr = id.uuidString
        sqlite3_bind_text(stmt, 1, idStr, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.deleteFailed }
    }

    func deleteAll() throws {
        guard sqlite3_exec(db, "DELETE FROM clipboard_items;", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.deleteFailed
        }
    }

    deinit { sqlite3_close(db) }
}

// MARK: - Clipboard Monitor

class ClipboardMonitor: ObservableObject {
    @Published var newClipboardText: String?
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval = 0.5

    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount > lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        guard validateClipboardText(text) else { return }
        DispatchQueue.main.async { self.newClipboardText = text }
    }

    func validateClipboardText(_ text: String) -> Bool {
        guard text.count <= 1_000_000 else { return false }
        guard text.utf16.count > 0 else { return false }
        return true
    }
}

// MARK: - Clipboard Store (persistent, per-item keys)

@MainActor
class ClipboardStore: ObservableObject {
    @Published var items: [EncryptedClipboardItem] = []
    @Published var showFirstLaunchNotice: Bool = false

    private let maxItems = 100
    private let encryption = EnhancedClipboardEncryption()
    private var database: EncryptedDatabase?
    private var itemKeys: [UUID: Data] = [:]

    init() {
        loadFromDatabase()
    }

    private func loadFromDatabase() {
        do {
            let db = try EncryptedDatabase()
            self.database = db
            let stored = try db.fetchAll(limit: maxItems)
            self.items = stored.map { $0.0 }
            for (item, key) in stored { itemKeys[item.id] = key }
        } catch {
            self.showFirstLaunchNotice = true
            print("ClipboardStore: starting fresh — \(error)")
        }
    }

    func addClipboardText(_ plaintext: String) async {
        do {
            let (encryptedItem, encryptedKey) = try encryption.encrypt(plaintext)
            if let db = database { try db.insert(encryptedItem, encryptedItemKey: encryptedKey) }
            itemKeys[encryptedItem.id] = encryptedKey
            items.insert(encryptedItem, at: 0)
            if items.count > maxItems {
                let removed = items.removeLast()
                try? database?.delete(removed.id)
                itemKeys.removeValue(forKey: removed.id)
            }
        } catch {
            print("Encryption failed: \(error)")
        }
    }

    func getDecryptedText(for item: EncryptedClipboardItem) -> String? {
        guard let encryptedKey = itemKeys[item.id] else { return nil }
        do {
            return try encryption.decrypt(item, encryptedItemKey: encryptedKey)
        } catch {
            print("Decryption failed: \(error)")
            return nil
        }
    }

    func pasteItem(_ item: EncryptedClipboardItem) {
        guard let plaintext = getDecryptedText(for: item) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plaintext, forType: .string)
    }

    func clearHistory() {
        items.removeAll()
        itemKeys.removeAll()
        try? database?.deleteAll()
    }
}

// MARK: - Authentication Manager (vaultclip-13n: Touch ID / biometric auth)
// IMPORTANT: NSFaceIDUsageDescription must be added to Info.plist manually in Xcode.

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false

    private var context = LAContext()
    private var lastActivityDate = Date()
    private let idleTimeout: TimeInterval = 5 * 60
    private var idleTimer: Timer?

    func authenticate() async {
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        do {
            let success = try await context.evaluatePolicy(
                policy, localizedReason: "Authenticate to access clipboard history"
            )
            isAuthenticated = success
            if success { startIdleTimer() }
        } catch {
            print("Authentication failed: \(error)")
            isAuthenticated = false
        }
    }

    func lock() {
        isAuthenticated = false
        idleTimer?.invalidate()
        idleTimer = nil
        context = LAContext()
    }

    func recordActivity() {
        lastActivityDate = Date()
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdleTimeout() }
        }
    }

    private func checkIdleTimeout() {
        guard isAuthenticated else { return }
        if Date().timeIntervalSince(lastActivityDate) >= idleTimeout { lock() }
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
            { _, _, userData -> OSStatus in
                Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue().callback?()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }
}

// MARK: - Window State

class WindowState: ObservableObject {
    @Published var isVisible = false

    func toggleVisibility() {
        isVisible.toggle()
        if isVisible {
            NSApp.activate(ignoringOtherApps: true)
            applyScreenProtection()
        }
    }

    /// vaultclip-g4x: prevent screen recording/screenshots from capturing clipboard content.
    private func applyScreenProtection() {
        for window in NSApplication.shared.windows {
            window.sharingType = .none
            if #available(macOS 13.0, *) {
                window.collectionBehavior.insert(.auxiliary)
            }
        }
    }
}

// MARK: - Protected Label (vaultclip-g4x: hides content from accessibility APIs)

struct ProtectedLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .accessibilityLabel("Clipboard item (content hidden for security)")
            .accessibilityValue("")
    }
}

// MARK: - Authentication Required View

struct AuthenticationRequiredView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("VaultClip Locked")
                .font(.headline)
            Text("Authenticate to access your clipboard history.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock") {
                Task { await authManager.authenticate() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .padding(32)
        .frame(width: 600, height: 400)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search clipboard...", text: $text).textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Clipboard Item Row

struct ClipboardItemRow: View {
    let item: EncryptedClipboardItem
    let store: ClipboardStore
    let isSelected: Bool
    @State private var preview: String = "Decrypting..."

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // vaultclip-g4x: ProtectedLabel hides content from accessibility APIs
                // vaultclip-0m6: SecurePreview limits decrypted exposure to 100 chars
                ProtectedLabel(text: preview)
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
        .onAppear { loadPreview() }
    }

    private func loadPreview() {
        preview = SecurePreview(encrypted: item).generatePreview()
    }
}

// MARK: - First Launch Notice

struct FirstLaunchNoticeView: View {
    let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle").font(.system(size: 32)).foregroundColor(.blue)
            Text("Welcome to VaultClip v0.2").font(.headline)
            Text("Clipboard history is now encrypted and stored persistently. Previous in-memory history was not retained.")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Get Started") { onDismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(width: 600, height: 400)
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var windowState: WindowState
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedItem: EncryptedClipboardItem?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.showFirstLaunchNotice {
                FirstLaunchNoticeView { store.showFirstLaunchNotice = false }
            } else {
                SearchBar(text: $searchText).padding()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ClipboardItemRow(
                                item: item, store: store,
                                isSelected: selectedItem?.id == item.id
                            )
                            .onTapGesture {
                                authManager.recordActivity()
                                handleSelection(item)
                            }
                        }
                    }
                    .padding()
                }
                HStack {
                    Text("\(store.items.count) items").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear All") { store.clearHistory() }.buttonStyle(.borderless)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 400)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            authManager.recordActivity()
        }
    }

    private func handleSelection(_ item: EncryptedClipboardItem) {
        store.pasteItem(item)
        windowState.isVisible = false
    }
}

// MARK: - Main App

class AppCoordinator {
    var cancellables = Set<AnyCancellable>()
}

@main
struct VaultClipApp: App {
    @StateObject private var clipboardMonitor = ClipboardMonitor()
    @StateObject private var clipboardStore = ClipboardStore()
    @StateObject private var windowState = WindowState()
    @StateObject private var authManager = AuthenticationManager()
    private let hotkeyManager = HotkeyManager()
    private let coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            // vaultclip-13n: gate content behind Touch ID / biometric auth
            if authManager.isAuthenticated {
                ContentView(store: clipboardStore, windowState: windowState)
                    .environmentObject(authManager)
            } else {
                AuthenticationRequiredView()
                    .environmentObject(authManager)
                    .onAppear { Task { await authManager.authenticate() } }
            }
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
        clipboardMonitor.$newClipboardText
            .compactMap { $0 }
            .sink { [clipboardStore] text in Task { await clipboardStore.addClipboardText(text) } }
            .store(in: &coordinator.cancellables)
    }

    private func setupHotkey() {
        hotkeyManager.register { [windowState] in
            DispatchQueue.main.async { windowState.toggleVisibility() }
        }
    }

    private func startMonitoring() {
        clipboardMonitor.startMonitoring()
    }
}
