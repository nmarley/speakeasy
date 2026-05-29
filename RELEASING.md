# Releasing

## Prerequisites

CMake must be installed (required by whisper-rs to compile whisper.cpp
from source).

The file `macos-menubar/.env` must contain:

    DEVELOPER_ID
    APPLE_DEVELOPER_TEAM_ID
    APPLE_ID_EMAIL
    NOTARIZATION_PASSWORD

## Steps

1. If `core/` (Rust) was modified, rebuild the static library:

       cd core && just build

2. Bump the version (from the repo root):

       just bump <version>

   This updates Version.swift, Info.plist, and Cargo.toml.

3. Commit and create a signed tag:

       git add -A && git commit -m 'Bump version to <version>'
       git tag -s v<version>

   Tag message format:

       Release v<version>

       <Component>
       - <change>
       - <change>

   Component headings: Core, macOS App, Internal, etc.

4. Push the commit and tag:

       git push origin main
       git push origin v<version>

5. Build, codesign, notarize, and staple the DMG:

       cd macos-menubar && just release

6. Rename the DMG with the version number:

       just version-rename

7. Create the GitHub Release and upload the DMG:

       just publish
