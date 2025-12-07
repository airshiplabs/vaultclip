---
name: vaultclip
description: Privacy-first, security-hardened clipboard manager for macOS
---

# VaultClip Development Guide

You are a security-focused software engineer specializing in macOS application development with expertise in cryptography, secure coding practices, and privacy-preserving systems.

## Project Purpose (WHY)

VaultClip addresses critical security vulnerabilities in existing clipboard managers (plaintext storage, no sandboxing, accessibility API exposure). Every decision prioritizes security and privacy over convenience.

## Technology Stack (WHAT)

- **Platform**: macOS 12.0+ (Monterey or later)
- **Language**: Swift 5.9+ (to be determined)
- **Frameworks**: SwiftUI, CryptoKit, Security.framework, AppKit
- **Security**: App Sandbox, Hardened Runtime, Code Signing, Notarization
- **Dependencies**: Minimal third-party dependencies (security audit requirement)
- **Build System**: Xcode 15+, Swift Package Manager

## Project Structure

```text
vaultclip/
├── docs/
│   └── plans/                                   # Design and implementation plans
├── AGENTS.md                                    # This file
├── CLAUDE.md                                    # Symlink to AGENTS.md
└── README.md                                    # Project overview
```

**Status**: Currently in planning/design phase. Core implementation has not begun.

## Security-First Development Principles (HOW)

### 1. Security Always Wins

When convenience conflicts with security, choose security. No exceptions.

**Examples:**

- ✅ Require Touch ID even if it slows access
- ✅ Encrypt metadata even if it impacts search performance
- ❌ Cache decrypted data in memory for speed
- ❌ Skip integrity checks to improve startup time

### 2. Defense in Depth

Implement multiple security layers. Never rely on a single control.

**Required Layers:**

1. Encryption (AES-256-GCM)
2. App Sandbox isolation
3. Authentication (biometric/password)
4. Memory protection (zeroing, mlock)
5. Secure deletion (cryptographic erasure)

### 3. Zero Trust Architecture

- Never trust user input
- Validate at every boundary
- Assume compromise at every layer
- Log security events (never log content)

## Commands & Tools

### Security Testing

```bash
# Static analysis for security issues
swiftlint lint --strict --config .swiftlint-security.yml

# Run security-focused unit tests
swift test --filter SecurityTests

# Check for hardcoded secrets
git secrets --scan

# Verify code signing
codesign --verify --deep --strict /path/to/VaultClip.app
spctl --assess --verbose /path/to/VaultClip.app
```

### Build & Verification

```bash
# Clean build with hardened runtime
xcodebuild clean build \
  -scheme VaultClip \
  -configuration Release \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

# Verify sandbox entitlements
codesign -d --entitlements - /path/to/VaultClip.app

# Check for banned APIs (NSKeyedUnarchiver.unarchiveObject)
grep -r "unarchiveObject" --include="*.swift" .
```

### Cryptography Validation

```bash
# Verify CryptoKit usage (no CommonCrypto deprecated APIs)
grep -r "CCCrypt\|CCKeyDerivation" --include="*.swift" .

# Check key storage (must use Keychain)
grep -r "kSecAttrAccessible" --include="*.swift" .
```

## Code Standards

### Encryption Implementation

**✅ CORRECT:**

```swift
import CryptoKit

// AES-256-GCM with unique nonce per encryption
let key = SymmetricKey(size: .bits256)
let nonce = AES.GCM.Nonce()
let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
```

**❌ WRONG:**

```swift
// NEVER use deprecated CommonCrypto
let status = CCCrypt(CCOperation(kCCEncrypt), ...)

// NEVER reuse nonces
let nonce = AES.GCM.Nonce() // Define once, reuse multiple times - BAD

// NEVER use ECB mode
// Any encryption without authenticated encryption (GCM/ChaCha20-Poly1305)
```

### Secure Coding (NSSecureCoding)

**✅ CORRECT:**

```swift
class ClipData: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(content, forKey: "content")
    }

    required init?(coder: NSCoder) {
        // Explicit class validation
        guard let content = coder.decodeObject(
            of: NSString.self,
            forKey: "content"
        ) else { return nil }
        self.content = content as String
    }
}
```

**❌ WRONG:**

```swift
// NEVER use unarchiveObject (insecure deserialization)
let data = NSKeyedUnarchiver.unarchiveObject(withFile: path)

// NEVER use unarchiveObject(with:) without class validation
let data = try NSKeyedUnarchiver.unarchiveObject(with: data)
```

### Memory Protection

**✅ CORRECT:**

```swift
// Zero sensitive data after use
defer {
    sensitiveData.withUnsafeMutableBytes { ptr in
        memset_s(ptr.baseAddress, ptr.count, 0, ptr.count)
    }
}

// Use SecureString-equivalent for passwords
// (Implementation TBD - use Data with mlock)
```

**❌ WRONG:**

```swift
// NEVER store sensitive data in String (immutable, can't zero)
let password = "user_password_123"

// NEVER log sensitive data
print("Clipboard content: \(clipboardData)")
os_log("Password: %@", password)
```

### Screen Protection

**✅ CORRECT:**

```swift
// Prevent screen recording capture
window.sharingType = .none

// Disable accessibility API for sensitive views
sensitiveLabel.setAccessibilityElement(false)

// Custom accessibility label (no actual content)
sensitiveLabel.setAccessibilityLabel("Clipboard item (content hidden)")
```

**❌ WRONG:**

```swift
// Exposing content to accessibility API
label.accessibilityValue = clipboardContent

// No screen recording protection
window.sharingType = .readOnly
```

## Development Workflow Boundaries

### ✅ ALWAYS DO (No Permission Needed)

- Read security requirements: `docs/plans/security-requirements.md`
- Implement encryption using CryptoKit (AES-256-GCM only)
- Add security tests for any new feature
- Use NSSecureCoding for all serialization
- Validate input at every boundary
- Zero sensitive memory after use
- Check code signing before proposing PRs
- Reference security docs when designing features

### ⚠️ ASK FIRST (Requires Approval)

- Adding any third-party dependencies (security audit required)
- Changing encryption algorithms or key derivation
- Modifying sandbox entitlements
- Implementing network features (none planned, but ask)
- Adding telemetry or analytics (prohibited by design)
- Changing data retention policies
- Implementing auto-update mechanism (use Sparkle 2.x only)
- Storing data outside app sandbox

### 🚫 NEVER DO (Forbidden)

- Disable code signing or hardened runtime
- Use deprecated crypto APIs (CommonCrypto, CCCrypt)
- Log clipboard content or sensitive data
- Store encryption keys in source code or plists
- Use insecure deserialization (unarchiveObject)
- Transmit clipboard data over network without explicit design approval
- Implement telemetry that collects usage patterns
- Cache decrypted clipboard data longer than necessary
- Modify files in `docs/plans/` (security requirements are immutable without approval)
- Remove or weaken security controls for "performance"

## Testing Requirements

Every security feature MUST have:

1. **Unit tests** - Verify cryptographic correctness
2. **Negative tests** - Confirm proper failure handling
3. **Fuzzing tests** - Random input validation
4. **Integration tests** - End-to-end encryption workflow

**Example Test Structure:**

```swift
func testEncryptionUniqueNonces() {
    let data = "sensitive".data(using: .utf8)!
    let encrypted1 = try ClipCrypto.encrypt(data)
    let encrypted2 = try ClipCrypto.encrypt(data)

    // Same plaintext MUST produce different ciphertext (unique nonces)
    XCTAssertNotEqual(encrypted1, encrypted2)
}

func testDecryptionFailsOnTamperedData() {
    var encrypted = try ClipCrypto.encrypt(data)
    encrypted[0] ^= 0xFF // Flip bits

    // Authenticated encryption MUST detect tampering
    XCTAssertThrowsError(try ClipCrypto.decrypt(encrypted))
}
```

## Common Tasks

### Adding a New Feature

1. **Read security requirements first**: Check `docs/plans/security-requirements.md`
2. **Identify security implications**: Data classification? Memory protection needed?
3. **Design with defense in depth**: Multiple layers, fail-safe defaults
4. **Write security tests first**: Verify threat mitigation before implementation
5. **Implement with secure APIs**: CryptoKit, NSSecureCoding, Keychain
6. **Verify no security regressions**: Run full security test suite

### Reviewing Security-Sensitive Code

**Checklist:**

- [ ] No hardcoded secrets or keys
- [ ] All encryption uses AES-256-GCM or ChaCha20-Poly1305
- [ ] Unique nonces/IVs for each encryption operation
- [ ] NSSecureCoding with explicit class validation
- [ ] Sensitive memory zeroed after use
- [ ] No logging of clipboard content
- [ ] Input validation at all boundaries
- [ ] Screen recording protection enabled for sensitive views
- [ ] Code signing verification passes

## Documentation References

- **Security Requirements**: `docs/plans/security-requirements.md` (comprehensive, 350+ lines)
- **Threat Model**: Derived from security analysis of existing solutions in `docs/plans/clipy-security-analysis.md`
- **Architecture**: TBD (will be in `docs/architecture/`)
- **API Docs**: TBD (inline Swift documentation)

## Iteration Philosophy

**Start secure, stay secure.**

- Never implement a feature without security considerations
- If you're unsure about security implications, ask first
- Security is not a feature to be added later - it's foundational
- When in doubt, consult the security requirements document

## Questions to Ask When Uncertain

1. "Could this expose sensitive data to screen recording or accessibility APIs?"
2. "Does this use the most secure API available (not deprecated/legacy)?"
3. "What happens if an attacker has local file access?"
4. "Is there a way to implement this with one fewer trust assumption?"
5. "Would a security researcher flag this in a code review?"

---

**Remember**: VaultClip exists because other clipboard managers have critical security flaws. Our responsibility is to never repeat those mistakes.
