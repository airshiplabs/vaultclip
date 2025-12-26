# VaultClip Scripts

This directory contains utility scripts for development, testing, and security verification.

## Available Scripts

### `verify-code-signing.sh`

Comprehensive code signing verification script that checks:

1. **Code signature validity** - Verifies the app is properly signed
2. **Hardened Runtime** - Ensures hardened runtime is enabled (required for notarization)
3. **Entitlements** - Verifies sandbox and security entitlements
4. **Bundle structure** - Checks Info.plist, executable, and code signature directory
5. **Signing identity** - Identifies the certificate used for signing
6. **Gatekeeper assessment** - Tests if macOS Gatekeeper will allow execution
7. **Security flags** - Checks for PIE, stack protection, and ARC

**Usage:**

```bash
# Automatic discovery (searches for VaultClip.app)
./scripts/verify-code-signing.sh

# Explicit path
./scripts/verify-code-signing.sh /path/to/VaultClip.app

# Example with build output
./scripts/verify-code-signing.sh ~/Library/Developer/Xcode/DerivedData/VaultClip-*/Build/Products/Debug/VaultClip.app
```

**Exit codes:**
- `0` - All checks passed
- `1` - Verification failed (critical issues found)
- `2` - App bundle not found

**Requirements:**
- macOS with Xcode Command Line Tools
- Built VaultClip.app bundle

**CI Integration:**

This script is automatically run in the GitHub Actions CI pipeline for release builds (pushes to `main` branch).

## Security Verification Workflow

When preparing a release:

1. **Build the app** in Release configuration with proper code signing
2. **Run verification script** to check signing and security posture
3. **Review warnings** and address any issues before distribution
4. **Notarize the app** (if distributing outside App Store)
5. **Test Gatekeeper** on a clean macOS system

## Adding New Scripts

When adding new scripts:

1. Use `.sh` extension for shell scripts
2. Make executable: `chmod +x scripts/your-script.sh`
3. Add shebang line: `#!/bin/bash` or `#!/usr/bin/env bash`
4. Include usage documentation in comments
5. Follow security-first principles from AGENTS.md
6. Document in this README

## Script Guidelines

- **Error handling**: Use `set -euo pipefail` for robustness
- **Output**: Use colored output for clarity (see `verify-code-signing.sh` for example)
- **Portability**: Test on macOS 12.0+ (VaultClip's minimum target)
- **Security**: Never log sensitive data (passwords, keys, clipboard content)
- **Documentation**: Include usage examples and exit code meanings

## Related Documentation

- [AGENTS.md](../AGENTS.md) - Development guidelines and security principles
- [Security Requirements](../docs/plans/security-requirements.md) - Comprehensive security requirements
- [Security Implementation Status](../docs/plans/security-implementation-status.md) - Current implementation tracking
