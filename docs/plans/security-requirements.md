# Security Requirements for a Secure Clipboard Manager

Based on the analysis of existing clipboard managers' security posture, here are comprehensive requirements for a secure clipboard application:

## 1. Data Protection & Encryption

### 1.1 Encryption at Rest

- **Requirement**: All clipboard data stored on disk MUST be encrypted using AES-256 or stronger
- **Key Management**:
  - Derive encryption keys from user's login keychain
  - Use separate keys for metadata vs. clipboard content
  - Support hardware-backed encryption (Secure Enclave/T2 chip integration)
- **Implementation**: Use Apple's `CryptoKit` framework or `CommonCrypto`

### 1.2 Memory Protection

- **Requirement**: Sensitive clipboard data in memory MUST be protected
- **Implementation**:
  - Use `SecureString`-equivalent for passwords/secrets
  - Zero memory immediately after use
  - Mark sensitive pages as non-pageable (prevent swap file exposure)
  - Use `mlock()` to prevent sensitive data from being written to swap

### 1.3 Secure Deletion

- **Requirement**: Deleted clipboard items MUST be securely erased
- **Implementation**:
  - Overwrite file data before deletion (multiple passes)
  - Use secure deletion APIs where available
  - Zero memory before deallocation
  - Invalidate encryption keys for deleted items

## 2. Access Control & Isolation

### 2.1 Application Sandboxing

- **Requirement**: Application MUST run in macOS App Sandbox
- **Entitlements**: Minimal required entitlements only
  - No network access (unless explicitly needed for sync)
  - File access limited to app container
  - No access to other app containers

### 2.2 Inter-Process Communication Security

- **Requirement**: Prevent other applications from reading clipboard history
- **Implementation**:
  - Use XPC services with proper entitlement checks
  - Implement caller validation for any IPC
  - Use Code Signing verification for IPC clients
  - Reject requests from unsigned or untrusted applications

### 2.3 Keychain Integration

- **Requirement**: Master encryption keys MUST be stored in macOS Keychain
- **Protection Class**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Access Control**: Require authentication for key access

## 3. Authentication & Authorization

### 3.1 Application Lock

- **Requirement**: Support locking the application with authentication
- **Options**:
  - Touch ID / Face ID authentication
  - Password protection
  - System login password verification
- **Triggers**:
  - After idle timeout (configurable)
  - When system locks
  - On demand via hotkey

### 3.2 Sensitive Data Protection

- **Requirement**: Extra protection for sensitive clipboard types
- **Implementation**:
  - Detect password/credit card patterns
  - Require re-authentication before showing sensitive items
  - Option to never store certain data types
  - Auto-expire sensitive items faster

## 4. Data Classification & Handling

### 4.1 Automatic Classification

- **Requirement**: Classify clipboard data by sensitivity
- **Categories**:
  - **Critical**: Passwords, API keys, private keys, credit cards
  - **Sensitive**: Phone numbers, emails, SSNs, addresses
  - **Private**: Messages, documents, code
  - **Public**: URLs, plain text, generic data
- **Detection**: Pattern matching, heuristics, ML-based classification

### 4.2 Differential Retention

- **Requirement**: Different retention policies per classification
- **Example Policy**:
  - Critical: 5 minutes or single use, then auto-delete
  - Sensitive: 1 hour, encrypted with extra protection
  - Private: 24 hours
  - Public: 30 days

### 4.3 Application-Based Rules

- **Requirement**: Automatic handling based on source application
- **Implementation**:
  - Never store clipboard from password managers
  - Never store from banking apps
  - Flag items from browsers as potentially sensitive
  - Configurable per-app policies

## 5. Network Security

### 5.1 No Unauthorized Network Access

- **Requirement**: Clipboard data MUST NOT be transmitted without explicit user consent
- **Implementation**:
  - No network entitlement by default
  - Audit all network code paths
  - Network calls require separate permission

### 5.2 Optional Secure Sync

- **Requirement**: If sync feature is added, it MUST be secure
- **Implementation**:
  - End-to-end encryption (E2EE)
  - Zero-knowledge architecture
  - TLS 1.3+ for transport
  - Certificate pinning
  - User controls: sync on/off per device, per item type

## 6. Audit & Monitoring

### 6.1 Audit Logging

- **Requirement**: Security-relevant events MUST be logged
- **Events to Log**:
  - Authentication attempts (success/failure)
  - Access to sensitive items
  - Configuration changes
  - Unusual access patterns
- **Privacy**: Do NOT log clipboard content, only metadata

### 6.2 Breach Detection

- **Requirement**: Detect potential unauthorized access
- **Implementation**:
  - Monitor file system access patterns
  - Detect if data files modified externally
  - Alert on integrity check failures
  - Rate limiting on authentication attempts

### 6.3 Integrity Verification

- **Requirement**: Detect tampering with stored clipboard data
- **Implementation**:
  - HMAC for each stored item
  - Periodic integrity checks
  - Alert user if tampering detected

## 7. Backup & Export Security

### 7.1 Backup Protection

- **Requirement**: Clipboard data in backups MUST be protected
- **Implementation**:
  - Exclude clipboard data from Time Machine by default
  - If included, ensure encrypted backups only
  - Use `NSURLIsExcludedFromBackupKey` for sensitive files
  - Warn user about backup implications

### 7.2 Export Controls

- **Requirement**: Exporting clipboard history MUST be secure
- **Implementation**:
  - Require authentication before export
  - Export to encrypted format only
  - Warn about security implications
  - Log export events

## 8. Privacy Features

### 8.1 Screen Capture & Accessibility Protection

- **Requirement**: Prevent clipboard content from appearing in screenshots, screen recordings, and screen readers
- **Implementation**:
  - Mark windows as private using `NSWindow.sharingType = .none` to prevent capture in screenshots and screen recordings
  - Use `NSView.isAccessibilityElement = false` for sensitive content views to prevent screen readers from accessing clipboard data
  - Implement custom accessibility labels that don't expose actual clipboard content
  - Protect against malicious apps using Accessibility API to read window content
  - Display warning indicator when screen recording is active
  - Optional: Blur or hide sensitive content when screen recording detected

### 8.2 Private Browsing Mode

- **Requirement**: Temporary mode that doesn't persist history
- **Features**:
  - All data stored in memory only
  - Cleared on exit or after timeout
  - No thumbnails or previews
  - Visual indicator active

### 8.3 Selective Privacy

- **Requirement**: User control over what's stored
- **Options**:
  - Whitelist/blacklist applications
  - Disable for specific data types (images, files, etc.)
  - Pause monitoring temporarily
  - Clear history for specific time ranges

## 9. Secure Development Practices

### 9.1 Secure Deserialization

- **Requirement**: Use secure coding/decoding APIs
- **Implementation**:
  - Use `NSSecureCoding` protocol
  - Implement `NSSecureCoding` for all stored types
  - Use `NSKeyedUnarchiver` with class validation
  - Never deserialize untrusted data without validation

### 9.2 Input Validation

- **Requirement**: Validate all data before processing
- **Areas**:
  - File paths (prevent path traversal)
  - Pasteboard types (validate formats)
  - User preferences (range checks)
  - Imported data (schema validation)

### 9.3 Secure Defaults

- **Requirement**: Default configuration MUST be secure
- **Defaults**:
  - Encryption: ON
  - Auto-lock: 5 minutes
  - Sensitive data retention: 5 minutes
  - App sandbox: ON
  - Network access: OFF
  - Backup inclusion: OFF

## 10. Compliance & Standards

### 10.1 Regulatory Compliance

- **Requirement**: Support compliance with privacy regulations
- **Features**:
  - GDPR: Right to erasure, data minimization
  - CCPA: Data access, deletion
  - HIPAA: Encryption, audit logs (if handling medical data)

### 10.2 Security Standards

- **Requirement**: Follow industry security standards
- **Standards**:
  - OWASP Mobile Security
  - Apple Security Guidelines
  - CIS Benchmarks
  - NIST Cybersecurity Framework

## 11. User Education & Transparency

### 11.1 Clear Security Indicators

- **Requirement**: User MUST understand security state
- **Indicators**:
  - Lock icon showing authentication status
  - Color coding for data sensitivity
  - Warning badges for unencrypted items
  - Clear labels for security settings

### 11.2 Security Warnings

- **Requirement**: Warn users about security implications
- **Scenarios**:
  - First launch: Explain what data is stored and how
  - Sensitive data detected: "This looks like a password"
  - Export: "This will create an unencrypted copy"
  - Backup: "Clipboard history will be in backups"

### 11.3 Documentation

- **Requirement**: Comprehensive security documentation
- **Topics**:
  - Encryption methodology
  - Data retention policies
  - Threat model
  - Best practices
  - Security features usage

## 12. Update & Patch Management

### 12.1 Secure Updates

- **Requirement**: Application updates MUST be secure
- **Implementation**:
  - Code signing with hardened runtime
  - Notarization by Apple
  - Automatic security updates
  - Secure update channel (HTTPS with certificate pinning)
  - Signature verification (use Sparkle 2.x with EdDSA)

### 12.2 Vulnerability Disclosure

- **Requirement**: Process for reporting security issues
- **Implementation**:
  - Public security policy
  - Responsible disclosure program
  - Security advisory notifications
  - Timely patching schedule

## 13. Performance vs. Security Trade-offs

### 13.1 Configurable Security Levels

- **Requirement**: Allow users to balance security and convenience
- **Levels**:
  - **Maximum Security**: Encryption, short retention, auth required
  - **Balanced**: Encryption, moderate retention, auto-lock
  - **Convenience**: Encryption only, longer retention, no auth
- **Never Compromise**: Encryption at rest (always required)

## 14. Implementation Priority

### Phase 1: Critical Security (MVP)

1. Encryption at rest (AES-256)
2. App Sandbox
3. Keychain integration for keys
4. Secure deletion
5. Exclude from backups by default

### Phase 2: Enhanced Protection

1. Authentication (Touch ID/password)
2. Data classification
3. Differential retention
4. Application-based rules
5. Memory protection
6. Screen recording/screen reader protection

### Phase 3: Advanced Features

1. Audit logging
2. Integrity verification
3. Secure sync (optional)
4. Private browsing mode
5. Breach detection

## Summary

A secure clipboard manager must balance **usability** with **security**. The key principles are:

1. **Encryption by default** - Never store plaintext on disk
2. **Isolation** - Sandbox prevents other apps from accessing data
3. **Authentication** - Require user verification for sensitive operations
4. **Data minimization** - Store only what's needed, delete aggressively
5. **Transparency** - Users understand what's stored and how it's protected
6. **Defense in depth** - Multiple layers of security
7. **Secure by default** - Security is not optional, it's built-in

These requirements would create a clipboard manager that provides similar functionality while protecting user data from common threat vectors including malware, unauthorized application access, and data breaches.

---

## Security Analysis of Existing Solutions

### Vulnerabilities Found

- **Data NOT encrypted at rest**: Clipboard data stored in plaintext on disk
- **No application sandboxing**: Any application running as the user can read clipboard history
- **No authentication**: No lock screen or access control
- **Persistent storage**: Clipboard history stored indefinitely (up to maxHistorySize setting)
- **Backup exposure**: Unencrypted clipboard data included in Time Machine backups

### Data at Risk

- Passwords (if copied/pasted)
- Credit card numbers
- Private messages and documents
- API keys and authentication tokens
- Personal identification numbers
- Any sensitive text/images copied

### Positive Security Aspects

- ✅ No network transmission of clipboard data
- ✅ No logging of clipboard content
- ✅ No analytics/telemetry (disabled)
- ✅ Application exclusion feature for password managers
- ✅ Uses standard macOS file permissions

### Risk Level

**MODERATE** - Standard practice for clipboard managers, but users should be aware of the security implications and take appropriate precautions (use exclusion lists, limit history size, avoid copying highly sensitive data).
