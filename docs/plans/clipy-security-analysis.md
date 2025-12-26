# Security Analysis of Clipy macOS Clipboard Manager

## Executive Summary

Completed comprehensive security review of Clipy codebase. Analysis focused on data exfiltration, insecure storage, injection vulnerabilities, and data exposure.

**Key Finding:** No HIGH severity vulnerabilities detected. One MEDIUM severity issue identified related to insecure deserialization.

## Analysis Methodology

- Phase 1: Repository Context Research (✓)
- Phase 2: Data Flow Analysis (✓)
- Phase 3: Vulnerability Assessment (✓)

## Scope Covered

- 48 Swift source files analyzed
- All network-related code examined
- All file I/O and persistence mechanisms reviewed
- Logging frameworks and usage checked
- Clipboard handling code traced
- External dependencies reviewed (Podfile)
- NSCoding/deserialization patterns examined
- XML parsing security checked

## Findings

### MEDIUM Severity

#### 1. Insecure Deserialization - NSKeyedUnarchiver (MEDIUM)

- **Files:**
  - `/Users/matthew/code/Clipy/Clipy/Sources/Services/PasteService.swift:60`
  - `/Users/matthew/code/Clipy/Clipy/Sources/Services/PasteService.swift:101`
  - `/Users/matthew/code/Clipy/Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift:337,342,353,368`
  - `/Users/matthew/code/Clipy/Clipy/Sources/Services/HotKeyService.swift:105,169`

- **Issue:** Uses deprecated `NSKeyedUnarchiver.unarchiveObject(withFile:)` and `NSKeyedUnarchiver.unarchiveObject(with:)` without class validation
- **Risk:** Potential arbitrary object instantiation if attacker can write to clipboard data storage paths
- **Exploit Scenario:**
  1. Attacker gains write access to `~/Library/Application Support/Clipy/*.data` files
  2. Crafts malicious serialized object
  3. User selects malicious item from clipboard history
  4. Malicious object deserialized, potentially executing code
- **Likelihood:** LOW (requires local file system access)
- **Recommendation:** Migrate to secure unarchiving APIs:

  ```swift
  // Replace:
  NSKeyedUnarchiver.unarchiveObject(withFile: path)

  // With:
  try NSKeyedUnarchiver.unarchivedObject(ofClass: CPYClipData.self, from: data)
  ```

## Security Strengths (No Issues Found)

### 1. Network Activity ✓

- **No clipboard data exfiltration detected**
- Only network activity: Sparkle auto-updater checking `https://clipy-app.com/appcast.xml`
- No analytics SDKs active (Fabric/Crashlytics commented out as TODOs)
- No HTTP requests in clipboard handling code

### 2. Data Storage ✓

- Clipboard data stored locally in `~/Library/Application Support/Clipy/`
- Uses Realm database for metadata
- Uses NSKeyedArchiver for clipboard content serialization
- Uses PINCache for thumbnail images
- **No encryption implemented**, but data never leaves device
- File permissions rely on macOS user-level protection

### 3. Logging ✓

- **No clipboard content logging detected**
- No `NSLog`, `print()`, or `os_log` calls that log clipboard data
- Crash reporting disabled (code present but not active)
- Only logs app lifecycle events like "applicationDidFinishLaunching"

### 4. Input Validation ✓

- XML parsing uses AEXML library for snippet import/export
- XML only processes user-initiated file selection (NSOpenPanel)
- No XXE vulnerabilities (AEXML is DOM-based parser)
- PropertyList parsing limited to NSPasteboard types (system-controlled)

### 5. Command Injection ✓

- **No shell execution or Process/NSTask usage in clipboard handling**
- `ExcludeAppService` checks process identifiers, but only reads (no execution)
- No AppleScript or osascript execution
- CGEvent used for paste simulation (safe, no string interpolation)

### 6. Path Traversal ✓

- File paths constructed safely using `NSSearchPathForDirectoriesInDomains`
- UUID-based filenames prevent traversal: `NSUUID().uuidString + ".data"`
- No user-controlled path components in file operations
- NSOpenPanel/NSSavePanel used for user file selection (sandboxed)

### 7. Authentication/Authorization ✓

- Properly requests Accessibility permission for paste functionality
- Only allows paste if `AXIsProcessTrustedWithOptions` returns true
- Application exclusion list stored in UserDefaults (user-controllable, appropriate)

### 8. Cryptography ✓

- No hardcoded secrets or API keys detected
- No weak crypto implementations
- Sparkle updater uses DSA signature verification (`dsa_pub.pem`)

### 9. WebViews ✓

- No WKWebView or WebView usage detected
- No XSS attack surface

## Data Flow Analysis Summary

### Clipboard Data Journey

1. **Capture:** `ClipService.create()` monitors `NSPasteboard.general` every 750μs
2. **Processing:** Creates `CPYClipData` from pasteboard types
3. **Storage:**
   - Metadata → Realm database
   - Content → NSKeyedArchiver → `~/Library/Application Support/Clipy/{UUID}.data`
   - Thumbnails → PINCache (memory/disk cache)
4. **Retrieval:** NSKeyedUnarchiver reads `.data` files on paste
5. **Deletion:** Files deleted via `FileManager.removeItem`

**No network transmission at any stage.**

## Risk Assessment

| Category | Risk Level | Justification |
| -------- | ---------- | ------------- |
| Data Exfiltration | ✓ NONE | No network activity with clipboard data |
| Insecure Storage | ✓ LOW | Plaintext local storage, but appropriate for use case |
| Command Injection | ✓ NONE | No shell execution |
| Path Traversal | ✓ NONE | Safe path construction |
| Deserialization | ⚠ MEDIUM | NSKeyedUnarchiver without class validation |
| XSS | ✓ NONE | No web views |
| Data Exposure | ✓ NONE | No logging of sensitive data |

## Recommendations

### Priority 1: Address Deserialization

```swift
// In PasteService.swift, ClipService.swift, etc.
// Replace unarchiveObject calls with secure alternatives
if let data = try? Data(contentsOf: URL(fileURLWithPath: clip.dataPath)),
   let clipData = try? NSKeyedUnarchiver.unarchivedObject(
       ofClass: CPYClipData.self,
       from: data
   ) {
    // Use clipData
}
```

### Priority 2: Documentation

- Document that clipboard data is stored unencrypted locally
- Add security section to README explaining data storage location
- Clarify that no data leaves the device

## Conclusion

**Clipy is generally secure for its intended use case.** The application:

- Does NOT send clipboard data over the internet ✓
- Does NOT log clipboard data insecurely ✓
- Has appropriate access controls ✓
- Has minimal attack surface ✓

The only identified vulnerability (insecure deserialization) is MEDIUM severity and requires local file system access to exploit, which is a relatively high barrier for attackers.

**Recommendation:** Safe to use with the understanding that clipboard history is stored unencrypted on disk (which is standard for clipboard managers).
