#! /bin/bash

# Check if an SVG file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <svg-file>"
    exit 1
fi

SVG_FILE="$1"
ICON_DIR="AppIcon.appiconset"

# Create the icon directory if it doesn't exist
mkdir -p "$ICON_DIR"

# Create the Contents.json file
cat > "$ICON_DIR/Contents.json" << EOF
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Generate all the required icon sizes
echo "Generating icons from $SVG_FILE..."

# Regular sizes
rsvg-convert -w 16 -h 16 "$SVG_FILE" -o "$ICON_DIR/icon_16x16.png"
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICON_DIR/icon_32x32.png"
rsvg-convert -w 128 -h 128 "$SVG_FILE" -o "$ICON_DIR/icon_128x128.png"
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICON_DIR/icon_256x256.png"
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICON_DIR/icon_512x512.png"

# @2x sizes
cp "$ICON_DIR/icon_32x32.png" "$ICON_DIR/icon_16x16@2x.png"
rsvg-convert -w 64 -h 64 "$SVG_FILE" -o "$ICON_DIR/icon_32x32@2x.png"
cp "$ICON_DIR/icon_256x256.png" "$ICON_DIR/icon_128x128@2x.png"
cp "$ICON_DIR/icon_512x512.png" "$ICON_DIR/icon_256x256@2x.png"
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$ICON_DIR/icon_512x512@2x.png"

echo "Done! Icons generated in $ICON_DIR/"
echo "You can now copy this directory into your .xcassets folder."

# Create the main asset catalog directory structure
mkdir -p "Assets.xcassets"

# Create the main Contents.json file
cat > "Assets.xcassets/Contents.json" << EOF
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Move the AppIcon.appiconset into the Assets.xcassets directory
mv "$ICON_DIR" "Assets.xcassets/"

echo "Asset catalog created at Assets.xcassets/"
