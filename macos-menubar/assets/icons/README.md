# SVG to Xcode Assets Generator

A simple tool that converts SVG files to Xcode asset catalogs with properly sized app icons.

## Requirements

- Docker

## Usage

All commands should be run from this same directory that the README is in.

1. First generate the asset catalog:

```bash
bash generate-asset-catalog.sh AppIcon.svg
```

... this results in a new `Assets.xcassets` directory in the current directory.

2. Next, generate the old style icon, which is a .icns file. This uses the
   generated `Assets.xcassets` asset catalog:

```bash
assets/icons/build-icns.sh
```

## How it works

1. Uses Docker to run librsvg (rsvg-convert) in an isolated environment
2. Generates all required icon sizes for macOS apps (16x16 to 512x512@2x)
3. Creates a properly structured Assets.xcassets catalog with AppIcon.appiconset
4. Outputs the asset catalog in the current directory
5. Uses the files in the asset catalog to generate a .icns file

Move the generated `Assets.xcassets` dir and `AppIcon.icns` file into your
project to use the icons.
