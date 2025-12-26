#!/bin/bash
# Code Signing Verification Script for VaultClip
# Usage: ./scripts/verify-code-signing.sh [path-to-VaultClip.app]
#
# Verifies:
# 1. Code signature validity
# 2. Hardened Runtime enabled
# 3. Sandbox entitlements present
# 4. No network entitlements (by default)
# 5. Proper bundle structure
#
# Exit codes:
#   0 - All checks passed
#   1 - Verification failed
#   2 - App bundle not found

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}VaultClip Code Signing Verification${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Find app bundle
find_app_bundle() {
    if [ $# -gt 0 ]; then
        APP_PATH="$1"
    else
        # Try common build locations
        if [ -f ".worktrees/v0.1-prototype/VaultClip.xcodeproj/project.pbxproj" ]; then
            # Find in DerivedData or build output
            APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "VaultClip.app" -type d 2>/dev/null | head -n 1)
        fi

        if [ -z "$APP_PATH" ]; then
            APP_PATH=$(find . -name "VaultClip.app" -type d 2>/dev/null | head -n 1)
        fi
    fi

    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}Error: VaultClip.app not found${NC}"
        echo "Please build the app first or provide path as argument:"
        echo "  $0 /path/to/VaultClip.app"
        exit 2
    fi

    echo -e "App bundle: ${BLUE}$APP_PATH${NC}"
    echo ""
}

# Check 1: Code signature validity
check_signature_validity() {
    echo "1. Verifying code signature validity..."

    if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
        print_pass "Code signature is valid"
    else
        print_fail "Code signature verification failed"
        echo "   Run: codesign --verify --deep --strict \"$APP_PATH\""
    fi
    echo ""
}

# Check 2: Hardened Runtime
check_hardened_runtime() {
    echo "2. Checking for Hardened Runtime..."

    local flags
    flags=$(codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep "^flags=" || echo "")

    if echo "$flags" | grep -q "runtime"; then
        print_pass "Hardened Runtime is enabled"
    else
        print_warn "Hardened Runtime not detected (required for notarization)"
        echo "   Enable in Xcode: Signing & Capabilities → Hardened Runtime"
    fi
    echo ""
}

# Check 3: Entitlements
check_entitlements() {
    echo "3. Verifying entitlements..."

    local entitlements
    entitlements=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null || echo "")

    if [ -z "$entitlements" ]; then
        print_warn "No entitlements found (may be unsigned)"
        echo ""
        return
    fi

    # Check for App Sandbox
    if echo "$entitlements" | grep -q "com.apple.security.app-sandbox.*true"; then
        print_pass "App Sandbox is enabled"
    else
        print_fail "App Sandbox NOT enabled (REQUIRED for VaultClip)"
        echo "   Add to VaultClip.entitlements:"
        echo "   <key>com.apple.security.app-sandbox</key>"
        echo "   <true/>"
    fi

    # Check for network entitlements (should NOT be present)
    if echo "$entitlements" | grep -q "com.apple.security.network.client"; then
        print_warn "Network client entitlement detected"
        echo "   VaultClip should not require network access by default"
        echo "   Remove unless explicitly needed and documented"
    else
        print_pass "No network entitlements (good for security)"
    fi

    # Check for file access entitlements (should be minimal)
    if echo "$entitlements" | grep -q "com.apple.security.files.user-selected"; then
        print_warn "User-selected file access entitlement present"
        echo "   Ensure this is necessary for VaultClip functionality"
    else
        print_pass "No user file access entitlements (minimal permissions)"
    fi

    echo ""
}

# Check 4: Bundle structure
check_bundle_structure() {
    echo "4. Verifying bundle structure..."

    # Check Info.plist exists
    if [ -f "$APP_PATH/Contents/Info.plist" ]; then
        print_pass "Info.plist present"
    else
        print_fail "Info.plist missing"
    fi

    # Check executable exists
    local executable
    executable=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")

    if [ -n "$executable" ] && [ -f "$APP_PATH/Contents/MacOS/$executable" ]; then
        print_pass "Executable ($executable) present"
    else
        print_fail "Executable missing or misconfigured"
    fi

    # Check for _CodeSignature
    if [ -d "$APP_PATH/Contents/_CodeSignature" ]; then
        print_pass "Code signature directory present"
    else
        print_warn "Code signature directory not found (may be unsigned)"
    fi

    echo ""
}

# Check 5: Signing identity
check_signing_identity() {
    echo "5. Checking signing identity..."

    local identity
    identity=$(codesign -dvvv "$APP_PATH" 2>&1 | grep "Authority=" | head -n 1 || echo "")

    if [ -n "$identity" ]; then
        print_info "Signing identity: ${identity#*=}"

        # Check if it's an ad-hoc signature (development only)
        if codesign -dvvv "$APP_PATH" 2>&1 | grep -q "Signature=adhoc"; then
            print_warn "Ad-hoc signature detected (development only, not distributable)"
            echo "   For distribution, sign with a valid Apple Developer ID"
        else
            print_pass "Signed with valid certificate"
        fi
    else
        print_warn "No signing identity found"
    fi

    echo ""
}

# Check 6: Gatekeeper assessment
check_gatekeeper() {
    echo "6. Running Gatekeeper assessment..."

    local assessment
    if assessment=$(spctl --assess --type execute --verbose "$APP_PATH" 2>&1); then
        print_pass "Gatekeeper assessment passed"
        print_info "Assessment: $assessment"
    else
        # Check if it's a notarization issue
        if echo "$assessment" | grep -q "notarized"; then
            print_warn "Gatekeeper assessment failed: Not notarized"
            echo "   For distribution outside App Store, notarization is required"
            echo "   See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution"
        else
            print_warn "Gatekeeper assessment failed"
            echo "   Details: $assessment"
        fi
    fi

    echo ""
}

# Check 7: Security flags
check_security_flags() {
    echo "7. Checking security-related compiler flags..."

    local executable
    executable=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")

    if [ -z "$executable" ] || [ ! -f "$APP_PATH/Contents/MacOS/$executable" ]; then
        print_warn "Cannot check security flags (executable not found)"
        echo ""
        return
    fi

    # Check for PIE (Position Independent Executable)
    if otool -hv "$APP_PATH/Contents/MacOS/$executable" 2>/dev/null | grep -q "PIE"; then
        print_pass "PIE (Position Independent Executable) enabled"
    else
        print_warn "PIE not detected (recommended for security)"
    fi

    # Check for stack canaries
    if otool -Iv "$APP_PATH/Contents/MacOS/$executable" 2>/dev/null | grep -q "___stack_chk"; then
        print_pass "Stack protection (stack canaries) enabled"
    else
        print_warn "Stack protection not detected"
    fi

    # Check for ARC (Automatic Reference Counting)
    if otool -Iv "$APP_PATH/Contents/MacOS/$executable" 2>/dev/null | grep -q "_objc_retain\|_objc_release"; then
        print_pass "ARC (Automatic Reference Counting) in use"
    else
        print_info "ARC usage not detected (may be pure Swift)"
    fi

    echo ""
}

# Summary
print_summary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo ""

    if [ $FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}✓ All checks passed!${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ All critical checks passed, but review warnings${NC}"
            exit 0
        fi
    else
        echo -e "${RED}✗ Verification failed${NC}"
        exit 1
    fi
}

# Main execution
main() {
    print_header
    find_app_bundle "$@"
    check_signature_validity
    check_hardened_runtime
    check_entitlements
    check_bundle_structure
    check_signing_identity
    check_gatekeeper
    check_security_flags
    print_summary
}

main "$@"
