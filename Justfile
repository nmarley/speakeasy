set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

VERSION := `git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0"`

# List available commands
default:
    @just --list

# Show current version from git tags
version:
    @echo "Current version is: {{ VERSION }}"

# Bump version across all source files
bump version:
    @echo "{{ version }}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Error: pass bare semver (e.g. just bump 0.6.6)" >&2; exit 1; }
    sed -i '' 's/static let current = ".*"/static let current = "{{ version }}"/' \
        macos-menubar/Sources/Speakeasy/Version.swift
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion {{ version }}" \
        macos-menubar/assets/Info.plist
    sed -i '' 's/^version = ".*"/version = "{{ version }}"/' \
        core/Cargo.toml && cd core && cargo check
    @echo "Version bumped to {{ version }}"
    @echo ""
    @echo "Next steps:"
    @echo "  git add -A && git commit -m 'Bump version to {{ version }}'"
    @echo "  git tag -s v{{ version }} -m 'Release v{{ version }}'"
