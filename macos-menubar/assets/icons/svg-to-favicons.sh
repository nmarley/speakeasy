#! /bin/bash

# Check if an SVG file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <svg-file>"
    exit 1
fi

SVG_FILE="$1"
ICON_DIR="favicons"

# Create the icon directory if it doesn't exist
mkdir -p "$ICON_DIR"

# Regular sizes
# rsvg-convert -w 16 -h 16 "$SVG_FILE" -o "$ICON_DIR/icon_16x16.png"
# rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICON_DIR/icon_32x32.png"
# rsvg-convert -w 128 -h 128 "$SVG_FILE" -o "$ICON_DIR/icon_128x128.png"
# rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICON_DIR/icon_256x256.png"
# rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICON_DIR/icon_512x512.png"

# Array of sizes
declare -A sizes=(
    [favicon-16x16.png]=16
    [favicon-32x32.png]=32
    [favicon-48x48.png]=48
    [favicon-64x64.png]=64
    [favicon-96x96.png]=96
    [favicon-128x128.png]=128
    [favicon-192x192.png]=192
    [favicon-256x256.png]=256
    [favicon-512x512.png]=512
    [apple-touch-icon.png]=180
    [apple-touch-icon-152x152.png]=152
    [apple-touch-icon-120x120.png]=120
    [apple-touch-icon-76x76.png]=76
    [apple-touch-icon-60x60.png]=60
)

for output in "${!sizes[@]}"; do
    size=${sizes[$output]}
    echo "Generating $output (${size}x${size})"
    rsvg-convert -w $size -h $size "$SVG_FILE" -o "${ICON_DIR}/${output}"
done

echo "✅ All favicons generated."
