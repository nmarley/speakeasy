# DMG Background and Icon Layout

Notes on how to create/update the DMG installer appearance.

## Background image

The background image (arrow graphic) lives at
`assets/background_arrow_dmg.tiff`.

## Creating/updating the DMG layout

1. Create a temporary writable DMG:

```sh
mkdir -p dmg-build
hdiutil create -size 10m -volname "Speakeasy" \
    -srcfolder dmg-build -fs HFS+ -format UDRW Speakeasy-temp.dmg
```

2. Attach the temporary DMG:

```sh
hdiutil attach -owners on Speakeasy-temp.dmg
```

3. In Finder, open the mounted volume and press Cmd+J to show View
   Options. Set the background image -- make sure you use the file from
   the mounted DMG, not a local copy.

4. Drag the app bundle and /Applications symlink to position them.

5. Wait a few seconds for Finder to save the `.DS_Store` file, then
   copy it out:

```sh
cp /Volumes/Speakeasy/.DS_Store assets/dmg_DS_Store
```

**Do not eject the DMG until the `.DS_Store` file is saved.**

6. Eject and clean up:

```sh
hdiutil detach /Volumes/Speakeasy
rm Speakeasy-temp.dmg
```

## Notarization workflow

The release pipeline (run via `just release`) performs
double notarization:

1. Notarize the app bundle (submitted as a zip via ditto)
2. Staple the notarization ticket to the app bundle
3. Create a DMG containing the stapled app
4. Notarize the DMG
5. Staple the notarization ticket to the DMG

Both the app bundle and the DMG are independently verified by
Gatekeeper. This is the correct approach per Apple's requirements.
