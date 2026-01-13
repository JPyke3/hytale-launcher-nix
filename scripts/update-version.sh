#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
readonly MANIFEST_URL="https://launcher.hytale.com/version/release/launcher.json"
readonly PACKAGE_FILE="package.nix"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# === Logging Functions (output to stderr to not interfere with function returns) ===
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# === Version/Hash Extraction ===
get_current_hash() {
    # Extract SRI hash from package.nix
    sed -n 's/.*sha256 = "\(sha256-[^"]*\)".*/\1/p' "$PACKAGE_FILE" | head -1
}

get_current_version() {
    # Extract version from package.nix
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$PACKAGE_FILE" | head -1
}

# === Manifest Fetching ===
fetch_manifest() {
    # Fetch the version manifest with user-agent header
    curl -sA "Mozilla/5.0" "$MANIFEST_URL" 2>/dev/null
}

parse_manifest_version() {
    local manifest="$1"
    echo "$manifest" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

parse_manifest_hash() {
    local manifest="$1"
    # Extract the linux amd64 sha256 hash
    echo "$manifest" | grep -A5 '"linux"' | grep -A2 '"amd64"' | grep '"sha256"' | sed 's/.*: *"\([^"]*\)".*/\1/'
}

convert_hex_to_sri() {
    local hex_hash="$1"
    # Convert hex SHA256 to SRI format using nix hash convert
    nix hash convert --hash-algo sha256 --to sri "sha256:$hex_hash" 2>/dev/null
}

# === Update Functions ===
update_package_hash() {
    local new_hash="$1"
    sed -i.bak "s|sha256 = \"sha256-[^\"]*\"|sha256 = \"$new_hash\"|" "$PACKAGE_FILE"
}

update_package_version() {
    local new_version="$1"
    sed -i.bak "s|version = \"[^\"]*\"|version = \"$new_version\"|" "$PACKAGE_FILE"
}

cleanup_backups() {
    rm -f "${PACKAGE_FILE}.bak"
}

restore_from_backup() {
    if [ -f "${PACKAGE_FILE}.bak" ]; then
        mv "${PACKAGE_FILE}.bak" "$PACKAGE_FILE"
        log_info "Restored package.nix from backup"
    fi
}

# === Validation ===
verify_build() {
    log_info "Verifying build..."
    if nix build .#hytale-launcher --no-link 2>&1; then
        log_info "Build verification passed"
        return 0
    else
        log_error "Build verification failed"
        return 1
    fi
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "$PACKAGE_FILE" ]; then
        log_error "flake.nix or $PACKAGE_FILE not found. Run from repository root."
        exit 1
    fi
}

ensure_required_tools() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required"; exit 1; }
    command -v curl >/dev/null 2>&1 || { log_error "curl is required"; exit 1; }
}

# === CLI Interface ===
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Hytale Launcher Nix package updater. Fetches version info from official manifest.

Options:
  --check       Only check for updates, don't apply (exit 1 if update available)
  --force       Force update even if versions match
  --help        Show this help message

Examples:
  $0              # Check and apply updates
  $0 --check      # CI mode: check only, exit 1 if update needed
  $0 --force      # Force regenerate (e.g., after flake.lock update)
EOF
}

# === Main Logic ===
main() {
    local check_only=false
    local force_update=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                check_only=true
                shift
                ;;
            --force)
                force_update=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    ensure_in_repository_root
    ensure_required_tools

    local current_version
    current_version=$(get_current_version)
    local current_hash
    current_hash=$(get_current_hash)

    log_info "Current version: $current_version"
    log_info "Current hash: $current_hash"

    # Fetch and parse manifest
    log_info "Fetching version manifest from upstream..."
    local manifest
    manifest=$(fetch_manifest)

    if [ -z "$manifest" ]; then
        log_error "Failed to fetch manifest"
        exit 1
    fi

    local latest_version
    latest_version=$(parse_manifest_version "$manifest")
    local latest_hex_hash
    latest_hex_hash=$(parse_manifest_hash "$manifest")

    if [ -z "$latest_version" ] || [ -z "$latest_hex_hash" ]; then
        log_error "Failed to parse manifest"
        exit 1
    fi

    local latest_hash
    latest_hash=$(convert_hex_to_sri "$latest_hex_hash")

    log_info "Latest version: $latest_version"
    log_info "Latest hash: $latest_hash"

    # Compare versions
    if [ "$current_version" = "$latest_version" ] && [ "$force_update" = false ]; then
        log_info "Already up to date!"
        exit 0
    fi

    log_info "Update available: $current_version -> $latest_version"

    if [ "$check_only" = true ]; then
        # Output for GitHub Actions
        echo "UPDATE_AVAILABLE=true"
        echo "CURRENT_VERSION=$current_version"
        echo "NEW_VERSION=$latest_version"
        echo "CURRENT_HASH=$current_hash"
        echo "NEW_HASH=$latest_hash"
        exit 1  # Non-zero indicates update available
    fi

    # Apply updates
    log_info "Applying update..."
    update_package_version "$latest_version"
    update_package_hash "$latest_hash"

    # Verify build
    if ! verify_build; then
        log_error "Build failed, restoring backup..."
        restore_from_backup
        exit 1
    fi

    cleanup_backups

    log_info "Successfully updated from $current_version to $latest_version"

    # Update flake.lock
    log_info "Updating flake.lock..."
    nix flake update 2>&1 || true

    # Show changes
    echo ""
    log_info "Changes applied:"
    git diff --stat "$PACKAGE_FILE" flake.lock 2>/dev/null || true
}

main "$@"
