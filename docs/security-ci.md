# Security CI GitHub Action

**Location**: `.github/workflows/security-ci.yml`

**Purpose**: Automated security verification, build testing, and project
health checks

---

## Overview

The Security CI workflow is a comprehensive 4-job pipeline that enforces
security best practices and prevents regressions in the VaultClip codebase.
It implements a **security-first, fail-fast** strategy where security checks
must pass before build and test steps run.

### When It Runs

- **Push events**: `main` branch and all `feature/*` branches
- **Pull requests**: Targeting `main` branch
- **Frequency**: Every commit to protected branches

### Quick Status Check

Visit: `https://github.com/airshiplabs/vaultclip/actions`

---

## Architecture

```text
┌─────────────────────────────────────────┐
│  Job 1: Security Verification (GATES)  │
│  Runner: macos-latest                    │
│  ✓ Crypto APIs   ✓ Deserialization      │
│  ✓ Keychain      ✓ Logging              │
│  ✓ Entitlements  ✓ Secrets              │
└─────────────────┬───────────────────────┘
                  │ (must pass)
                  ↓
        ┌─────────────────────┐
        │  Job 2: Build/Test  │
        │  Runner: macos-latest│
        │  ✓ Build             │
        │  ✓ Tests             │
        │  ✓ Code Signing      │
        └─────────────────────┘

┌─────────────────────────────────────────┐
│  Job 3: Documentation (Parallel)        │
│  Runner: ubuntu-latest                   │
│  ✓ Required docs  ✓ TODO markers        │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Job 4: Beads Tracking (Parallel)       │
│  Runner: ubuntu-latest                   │
│  ✓ Issue tracking  ✓ Markdown TODOs     │
└─────────────────────────────────────────┘
```

---

## Job 1: Security Verification (GATE)

**Critical**: All other jobs depend on this passing.

### 1.1 Banned Crypto APIs Check

**Severity**: ❌ **FAILS BUILD**

**What it checks**:

```bash
grep -r "CCCrypt\|CCKeyDerivation" --include="*.swift" .
```

**Why it matters**: Deprecated CommonCrypto APIs are error-prone and lack
modern security features. VaultClip must use CryptoKit (AES-256-GCM).

**Example failure**:

```swift
// ❌ BANNED - Will fail CI
let status = CCCrypt(kCCEncrypt, ...)

// ✅ CORRECT - Will pass
import CryptoKit
let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
```

**How to fix**:

1. Replace all `CCCrypt`, `CCKeyDerivation` calls with CryptoKit
   equivalents
2. See `docs/plans/security-requirements.md` section 1.1 for correct
   implementations
3. Run locally: `grep -r "CCCrypt" --include="*.swift" .`

---

### 1.2 Insecure Deserialization Check

**Severity**: ❌ **FAILS BUILD**

**What it checks**:

```bash
grep -r "unarchiveObject" --include="*.swift" .
```

**Why it matters**: `NSKeyedUnarchiver.unarchiveObject()` allows arbitrary
object instantiation, leading to potential code execution vulnerabilities.

**Example failure**:

```swift
// ❌ BANNED - Will fail CI
let data = NSKeyedUnarchiver.unarchiveObject(withFile: path)
let obj = try NSKeyedUnarchiver.unarchiveObject(with: data)

// ✅ CORRECT - Will pass
let obj = try NSKeyedUnarchiver.unarchivedObject(
    ofClass: MyClass.self,
    from: data
)
```

**How to fix**:

1. Use `unarchivedObject(ofClass:from:)` with explicit class validation
2. Implement `NSSecureCoding` for all serializable classes
3. See Clipy security analysis: `docs/plans/clipy-security-analysis.md`
   section on insecure deserialization

---

### 1.3 Keychain Configuration Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
grep -r "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" \
  --include="*.swift" .
```

**Why it matters**: Encryption keys stored in Keychain must use
device-locked protection class to prevent extraction when device is locked.

**Example warning**:

```swift
// ⚠️ WARNING - Weaker protection
kSecAttrAccessible: kSecAttrAccessibleAlways

// ✅ CORRECT - Device-locked
kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

**How to fix**:

1. Ensure all Keychain operations use
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
2. See VaultClipApp.swift:54 for reference implementation

---

### 1.4 Sensitive Data Logging Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
grep -r "print.*clipboard\|os_log.*password\|NSLog.*content" \
  --include="*.swift" .
```

**Why it matters**: Logging clipboard content or passwords exposes
sensitive user data in system logs, crash reports, and console output.

**Example warning**:

```swift
// ⚠️ WARNING - Logs sensitive data
print("Clipboard content: \(clipboardText)")
os_log("Password: %@", password)

// ✅ CORRECT - Logs events only
print("Encryption failed: \(error)")  // Error type, not content
os_log("Clipboard item captured")     // Event, not data
```

**How to fix**:

1. Never log clipboard content, passwords, or encryption keys
2. Log events, errors, and metadata only
3. See AGENTS.md section "Memory Protection" for guidance

---

### 1.5 Sandbox Entitlements Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
# Check for App Sandbox
find . -name "*.entitlements" | \
  xargs grep "com.apple.security.app-sandbox"

# Check for network entitlements (should NOT be present)
find . -name "*.entitlements" | \
  xargs grep "com.apple.security.network.client"
```

**Why it matters**: App Sandbox isolation is critical for security.
Network entitlements should only be added if explicitly required and
documented.

**How to fix**:

1. Ensure `VaultClip.entitlements` contains
   `com.apple.security.app-sandbox = true`
2. Remove network entitlements unless required by design
3. Document any entitlement additions in security requirements

---

### 1.6 Hardcoded Secrets Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
grep -rE "(password|secret|api_key|token)\s*=\s*['\"][^'\"]+['\"]" \
  --include="*.swift" .
```

**Why it matters**: Hardcoded credentials in source code can be extracted
by attackers.

**Example warning**:

```swift
// ⚠️ WARNING - Hardcoded secret
let apiKey = "sk_live_123456789abcdef"

// ✅ CORRECT - Load from Keychain or environment
let apiKey = try KeychainManager.getAPIKey()
```

**How to fix**:

1. Store secrets in Keychain, not source code
2. Use environment variables for CI/CD secrets
3. Review all matches manually to confirm they're not real secrets

---

## Job 2: Build and Test

**Dependencies**: Requires Job 1 (Security Verification) to pass

### 2.1 Project Detection

**Graceful handling**: If no `.xcodeproj` is found, build/test steps are
skipped (not failed). This allows documentation-only changes during
planning phase.

```bash
# Check runs automatically
find . -name "*.xcodeproj" -type d
```

**Output**: Sets `check-xcode.outputs.found` flag

---

### 2.2 Build VaultClip

**When it runs**: Only if Xcode project exists

**Configuration**:

- **Scheme**: VaultClip
- **Configuration**: Debug
- **Platform**: macOS
- **Code Signing**: Disabled (CI doesn't need signed builds)

**Command**:

```bash
xcodebuild clean build \
  -project "*.xcodeproj" \
  -scheme VaultClip \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

**Common failures**:

- **Compilation errors**: Fix Swift syntax/type errors
- **Missing dependencies**: Ensure all frameworks are linked
- **Target configuration**: Verify scheme "VaultClip" exists

---

### 2.3 Run Security Tests

**When it runs**: Only if Xcode project exists

**What it tests**:

- Encryption correctness (unique nonces, AES-256-GCM)
- Tamper detection (authenticated encryption)
- Keychain integration (key persistence)
- Memory protection (zeroing sensitive data)
- Input validation (size limits, UTF-8 encoding)

**Test suite**: `VaultClipTests/SecurityTests.swift`

**Command**:

```bash
xcodebuild test \
  -project "*.xcodeproj" \
  -scheme VaultClip \
  -destination 'platform=macOS'
```

**Common failures**:

- **Test failures**: Review test output in artifacts
- **Encryption regression**: Verify CryptoKit usage
- **Keychain errors**: May need cleanup in test setup

---

### 2.4 Upload Test Results

**When it runs**: Always (even if tests fail), if Xcode project exists

**What it captures**:

- `.xcresult` bundles from Xcode DerivedData
- Full test logs, screenshots, performance metrics

**Retention**: 30 days

**How to download**:

1. Go to failed workflow run
2. Scroll to "Artifacts" section
3. Download `test-results.zip`
4. Open `.xcresult` in Xcode: `xed test-results/*.xcresult`

---

### 2.5 Code Signing Verification

**When it runs**: Only on `main` branch pushes, if Xcode project exists

**What it checks**:

- Valid code signature
- Hardened Runtime enabled
- Correct entitlements (sandbox, no network)
- Security compiler flags (PIE, stack protection, ARC)

**Script**: `scripts/verify-code-signing.sh`

**Note**: This step allows warnings (non-blocking) since code signing may
not be fully configured in CI environment.

---

## Job 3: Documentation Verification

**Runner**: `ubuntu-latest` (faster for file checks)

### 3.1 Required Documentation

**Severity**: ❌ **FAILS BUILD**

**Files checked**:

- `README.md` - Project overview
- `CLAUDE.md` - AI agent development guide
- `docs/plans/security-requirements.md` - Security specification

**How to fix**: Ensure all three files exist and are committed to
repository.

---

### 3.2 TODO Markers Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
grep -r "TODO\|FIXME\|HACK" --include="*.swift" .
```

**Why it matters**: VaultClip uses `bd` (beads) for issue tracking. TODO
comments scatter work items and lack dependency tracking.

**How to fix**:

1. Convert TODO comments to beads issues: `bd create "Fix X" -t task`
2. Remove TODO comments from code
3. Link related work: `bd create "..." --deps discovered-from:<parent-id>`

---

## Job 4: Beads Issue Tracking

**Runner**: `ubuntu-latest`

### 4.1 Beads Issues Analysis

**What it does**:

- Detects `.beads/issues.jsonl` presence
- Counts open issues
- Lists high-priority issues (P0/P1) for visibility

**Output example**:

```text
✓ Beads issue tracking file found
Open issues: 7
High-priority issues:
  - vaultclip-zbt: Memory protection uses memset_s but no mlock
    for swap prevention (P1)
  - vaultclip-0m6: Decrypted text exposed in memory for UI
    preview (P1)
  - vaultclip-g4x: Missing screen recording protection (P1)
  - vaultclip-enr: Xcode not installed - cannot build/test
    prototype (P1)
```

**How to use**:

- Check workflow output to see high-priority work items
- Use `bd ready` locally to find unblocked issues
- Review P0/P1 issues before releases

---

### 4.2 Markdown TODO Lists Check

**Severity**: ⚠️ **WARNING ONLY**

**What it checks**:

```bash
grep -rE "- \[ \]|TODO:" --include="*.md" .
```

**Exclusions**: `.git/` and `history/` directories

**How to fix**: Convert Markdown checklists to beads issues for better
tracking and dependency management.

---

## Interpreting Results

### ✅ All Checks Passed

```text
✓ Security Verification
✓ Build and Test
✓ Documentation Verification
✓ Beads Issue Tracking Check
```

**Action**: None required. Safe to merge.

---

### ❌ Security Verification Failed

```text
✗ Security Verification
○ Build and Test (skipped)
✓ Documentation Verification
✓ Beads Issue Tracking Check
```

**Action**:

1. Review security check logs
2. Fix banned API usage or insecure patterns
3. Push fix and re-run CI
4. **Do not bypass security checks**

---

### ❌ Build Failed

```text
✓ Security Verification
✗ Build and Test
✓ Documentation Verification
✓ Beads Issue Tracking Check
```

**Action**:

1. Download test results artifact
2. Review compilation errors
3. Fix and re-run locally: `xcodebuild clean build`
4. Push fix

---

### ⚠️ Warnings Present

```text
✓ Security Verification (2 warnings)
✓ Build and Test
✓ Documentation Verification
✓ Beads Issue Tracking Check
```

**Action**:

1. Review warning details in logs
2. Address warnings if they indicate real issues
3. Warnings don't block merge, but should be triaged

---

## Local Testing

### Run Security Checks Locally

```bash
# Banned crypto APIs
grep -r "CCCrypt\|CCKeyDerivation" --include="*.swift" .

# Insecure deserialization
grep -r "unarchiveObject" --include="*.swift" .

# Keychain configuration
grep -r "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" \
  --include="*.swift" .

# Sensitive data logging
grep -r "print.*clipboard\|os_log.*password\|NSLog.*content" \
  --include="*.swift" .

# Hardcoded secrets
grep -rE "(password|secret|api_key|token)\s*=\s*['\"][^'\"]+['\"]" \
  --include="*.swift" .
```

### Run Build Locally

```bash
# Navigate to worktree with Xcode project
cd .worktrees/v0.1-prototype

# Build
xcodebuild clean build \
  -project VaultClip.xcodeproj \
  -scheme VaultClip \
  -configuration Debug

# Test
xcodebuild test \
  -project VaultClip.xcodeproj \
  -scheme VaultClip \
  -destination 'platform=macOS'
```

### Run Code Signing Verification

```bash
./scripts/verify-code-signing.sh
```

---

## Configuration

### Changing Xcode Version

**Current**: `latest-stable` (currently Xcode 16.4 on macos-latest)

**To specify a version**:

```yaml
- name: Setup Xcode
  uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '16.4'  # Specific version
    # OR
    xcode-version: latest-stable  # Most recent stable
    # OR
    xcode-version: latest  # Includes betas
```

**Available versions**: See
[runner-images/macos-15-Readme.md][macos-readme]

[macos-readme]: https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md#xcode

---

### Adding Security Checks

**Location**: `.github/workflows/security-ci.yml` → `security-checks` job

**Example**: Add check for weak hash functions

```yaml
- name: Check for weak hash algorithms
  run: |
    echo "Checking for MD5/SHA1 usage..."
    if grep -rE "Insecure\.(MD5|SHA1)" --include="*.swift" . ; then
      echo "ERROR: Found weak hash algorithms. Use SHA256+ only."
      exit 1
    fi
    echo "✓ No weak hash algorithms found"
```

---

### Disabling Jobs (Not Recommended)

To temporarily disable a job (e.g., for debugging):

```yaml
jobs:
  security-checks:
    name: Security Verification
    runs-on: macos-latest
    if: false  # ⚠️ DISABLES JOB - Remove after debugging
```

**Warning**: Never disable security checks in production branches.

---

## Best Practices

### ✅ Do This

1. **Run security checks locally** before pushing
2. **Review all warnings** even if they don't block CI
3. **Download test artifacts** when investigating failures
4. **Track discovered issues** in beads during development
5. **Keep documentation current** (README, CLAUDE.md,
   security-requirements.md)

### ❌ Don't Do This

1. **Don't bypass security checks** by commenting out code temporarily
2. **Don't commit TODO comments** - use beads instead
3. **Don't ignore warnings** - they often indicate real issues
4. **Don't push WIP commits** to main - use feature branches
5. **Don't disable CI jobs** without team discussion

---

## Troubleshooting

### "Could not find Xcode version that satisfied version spec"

**Cause**: Specified Xcode version not available on `macos-latest` runner.

**Fix**: Use `xcode-version: latest-stable` or check available versions in
[runner-images docs][runner-docs].

[runner-docs]: https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md#xcode

---

### "Build failed: Scheme 'VaultClip' is not currently configured"

**Cause**: Xcode scheme not shared or named differently.

**Fix**:

1. Open Xcode
2. Product → Scheme → Manage Schemes
3. Check "Shared" for VaultClip scheme
4. Commit `.xcodeproj/xcshareddata/xcschemes/VaultClip.xcscheme`

---

### "Test failed: Unable to find test target"

**Cause**: Test target not included in scheme or missing from project.

**Fix**:

1. Verify `VaultClipTests` target exists
2. Product → Scheme → Edit Scheme → Test → Add VaultClipTests
3. Ensure test target is checked

---

### "Artifact upload failed: No files found"

**Cause**: Tests didn't run or `.xcresult` path is incorrect.

**Fix**: This is expected if tests are skipped. Not a blocker.

---

## Related Documentation

- **Security Requirements**: `docs/plans/security-requirements.md`
  (350+ requirements)
- **Security Implementation Status**:
  `docs/plans/security-implementation-status.md` (tracking)
- **Code Signing Verification**: `scripts/README.md` (script usage)
- **Clipy Security Analysis**: `docs/plans/clipy-security-analysis.md`
  (threat model)
- **Development Guide**: `AGENTS.md` (comprehensive guide)

---

## Maintenance

### Reviewing CI Effectiveness

**Monthly checklist**:

- [ ] Review failed builds - are checks catching real issues?
- [ ] Check warnings - should any be promoted to failures?
- [ ] Verify Xcode version is current
- [ ] Audit security check patterns for false positives
- [ ] Review artifact retention (30 days sufficient?)

### Updating for New Requirements

When adding new security requirements:

1. Add check to `security-checks` job
2. Document in this file
3. Update `docs/plans/security-requirements.md`
4. Test locally before pushing

---

## Questions?

- **CI failing unexpectedly?** Check
  [GitHub Actions status](https://www.githubstatus.com/)
- **Need to add a check?** See "Adding Security Checks" section above
- **Found a bug in CI?** Create issue:
  `bd create "CI: <description>" -t bug -p 1`
- **Performance issues?** Consider splitting jobs or using caching

---

**Last Updated**: 2025-12-26

**Maintainer**: VaultClip Development Team

**Workflow Version**: 1.0
