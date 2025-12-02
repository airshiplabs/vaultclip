# VaultClip

## A privacy-first, security-hardened clipboard manager for macOS

VaultClip is a modern clipboard manager built from the ground up with security and privacy as core design principles. Unlike traditional clipboard managers that store your sensitive data in plaintext, VaultClip encrypts everything, sandboxes its operations, and gives you granular control over what gets stored and for how long.

## Why VaultClip?

Traditional clipboard managers have fundamental security vulnerabilities:

- Clipboard history stored in plaintext on disk
- No application sandboxing (any app can read your clipboard history)
- No authentication or access control
- Sensitive data (passwords, credit cards) stored indefinitely
- Vulnerable to malware and unauthorized access
- Clipboard content exposed to screen recording and accessibility APIs

VaultClip addresses these issues with a defense-in-depth security architecture.

## Key Features

### Security First

- **AES-256 Encryption at Rest** - All clipboard data encrypted before hitting disk
- **App Sandboxing** - Isolated from other applications to prevent unauthorized access
- **Touch ID / Face ID Authentication** - Lock and unlock with biometric authentication
- **Secure Deletion** - Cryptographically secure data erasure
- **Memory Protection** - Sensitive data protected in memory and zeroed after use
- **No Network Access** - Zero data exfiltration, everything stays local

### Smart Data Classification

- **Automatic Sensitivity Detection** - Identifies passwords, API keys, credit cards, PINs
- **Differential Retention Policies** - Sensitive data auto-expires quickly, public data persists longer
- **Application-Aware Rules** - Never store clipboard from password managers or banking apps
- **Per-Item Encryption** - Each clipboard item encrypted with unique keys

### Privacy Features

- **Private Browsing Mode** - Temporary clipboard that exists only in memory
- **Screen Capture & Accessibility Protection** - Prevents sensitive data from appearing in screenshots, screen recordings, and unauthorized screen readers
- **Audit Logging** - Track access without logging content
- **Selective Storage** - Whitelist/blacklist apps and data types
- **Backup Protection** - Excluded from Time Machine by default

### User Experience

- **Fast Global Search** - Find clipboard items instantly
- **Smart Previews** - Safe rendering of text, images, and files
- **Keyboard-Driven** - Powerful hotkeys for everything
- **Custom Snippets** - Save frequently used text with encryption
- **Multi-Format Support** - Text, images, files, and more

## Security Architecture

VaultClip implements multiple layers of security:

1. **Encryption Layer**: All data encrypted with AES-256-GCM using keys derived from macOS Keychain
2. **Isolation Layer**: macOS App Sandbox prevents unauthorized access from other applications
3. **Authentication Layer**: Biometric or password authentication required for sensitive operations
4. **Classification Layer**: ML-based detection identifies and protects sensitive data automatically
5. **Audit Layer**: Tamper-evident logging of security events without exposing content

See [Security Requirements](docs/plans/security-requirements.md) for comprehensive security documentation.

## Comparison to Existing Solutions

| Feature | VaultClip | Clipy | Maccy | Others |
|---------|-----------|-------|-------|--------|
| Encryption at Rest | ✅ AES-256 | ❌ Plaintext | ❌ Plaintext | ❌ Plaintext |
| App Sandboxing | ✅ Yes | ❌ No | ❌ No | ❌ No |
| Authentication | ✅ Touch ID/Password | ❌ No | ❌ No | ⚠️ Some |
| Data Classification | ✅ Automatic | ❌ No | ❌ No | ❌ No |
| Memory Protection | ✅ Yes | ❌ No | ❌ No | ❌ No |
| Network Access | ✅ None | ✅ None | ✅ None | ⚠️ Varies |
| Secure Deletion | ✅ Cryptographic | ❌ Basic | ❌ Basic | ❌ Basic |
| Screen Recording Protection | ✅ Yes | ❌ No | ❌ No | ❌ No |
| Screen Reader Protection | ✅ Yes | ❌ No | ❌ No | ❌ No |

VaultClip was created after a [comprehensive security analysis](docs/plans/clipy-security-analysis.md) of existing clipboard managers revealed critical vulnerabilities that needed to be addressed.

## Installation

**Status**: VaultClip is currently in active development. Installation instructions will be available when the first release is ready.

### Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon or Intel Mac
- 50MB available disk space

## Usage

**Status**: Coming soon. VaultClip will feature:

- Global hotkey to open clipboard history
- Keyboard navigation and search
- Click or press Enter to paste
- Right-click for advanced options
- Settings panel for customization

## Security Features in Detail

### Encryption

- **Algorithm**: AES-256-GCM with authenticated encryption
- **Key Derivation**: PBKDF2 with keys stored in macOS Keychain
- **Key Storage**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Per-Item Keys**: Each clipboard item encrypted with unique key
- **Metadata Protection**: Encrypted metadata prevents inference attacks

### Data Classification Levels

- **Critical** (passwords, keys): 5 minutes retention, require auth to view
- **Sensitive** (emails, phone numbers): 1 hour retention, flagged in UI
- **Private** (messages, documents): 24 hours retention
- **Public** (URLs, generic text): 30 days retention

### Secure Development

- Uses `NSSecureCoding` for all serialization
- Input validation on all data paths
- No deprecated APIs (e.g., `NSKeyedUnarchiver.unarchiveObject`)
- Regular security audits and penetration testing
- Code signing with hardened runtime
- Notarized by Apple

## Documentation

- [Security Requirements](docs/plans/security-requirements.md) - Comprehensive security design document
- [Security Analysis](docs/plans/clipy-security-analysis.md) - Research that motivated VaultClip

## Development Status

**Current Phase**: Planning & Design

- [x] Security requirements definition
- [x] Threat modeling
- [x] Architecture design
- [ ] Core encryption implementation
- [ ] Clipboard monitoring system
- [ ] UI/UX development
- [ ] Testing & security audit
- [ ] Beta release

## Contributing

Contributions are welcome! This project prioritizes:

1. Security correctness over features
2. Code clarity over cleverness
3. Privacy over convenience
4. Thorough testing over rapid shipping

Security vulnerabilities should be reported privately to the maintainers.

## License

TBD

## Acknowledgments

VaultClip builds on lessons learned from existing open-source clipboard managers, while addressing common security limitations with modern cryptographic practices and defense-in-depth architecture.

---

**Note**: VaultClip is designed for users who handle sensitive data and need stronger security guarantees than traditional clipboard managers provide. While convenience is important, security and privacy are never compromised.
