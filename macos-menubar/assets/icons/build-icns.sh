#! /bin/bash

if [ ! -d ./Assets.xcassets ]; then
    echo "Assets.xcassets not found"
    echo "Please run the generate-asset-catalog.sh script first to generate the asset catalog"
    exit 1
fi

# Remove the AppIcon.iconset directory if it exists
if [ -d AppIcon.iconset ]; then
    echo "Removing old AppIcon.iconset directory, starting fresh"
    rm -rf AppIcon.iconset
fi

mkdir -p AppIcon.iconset

for size in 16 32 128 256 512; do
    for scale in "" "@2x"; do
        filename="icon_${size}x${size}${scale}.png"
        cp "./Assets.xcassets/AppIcon.appiconset/${filename}" "./AppIcon.iconset/" 2>/dev/null || echo "Warning: ${filename} not found"
    done
done

iconutil -c icns AppIcon.iconset

echo "Generated AppIcon.icns"

# clean up
echo "Cleaning up..."
rm -fr AppIcon.iconset
echo "... done"
