#! /bin/bash

DOCKER_IMAGE_NAME="svg-icon-generator"
SVG_FILENAME="$1"

if [ -z "$SVG_FILENAME" ]; then
    echo "Please provide a SVG file name"
    exit 1
fi

echo "Generating icons from $SVG_FILENAME"

# Build Docker image if it doesn't exist
if ! docker image inspect "$DOCKER_IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building Docker image ${DOCKER_IMAGE_NAME}"
    docker build --no-cache -t "$DOCKER_IMAGE_NAME" .
fi

# Run the Docker container
echo "Generating favicons using Docker"
docker run --rm \
    -v "$(pwd):/app" \
    --entrypoint /svg-to-favicons.sh \
    "$DOCKER_IMAGE_NAME" "$SVG_FILENAME"

# Check if the Assets.xcassets directory was created
if [ -d "favicons" ]; then
    # Bundle favicon.ico file
    (cd favicons && convert favicon-16x16.png favicon-32x32.png favicon-48x48.png favicon-64x64.png favicon-128x128.png favicon.ico)
    echo "Favicon generation complete! Favicons are at ./favicons"
    echo "Please move the favicons into the appropriate place in your project"
else
    echo "Error: Favicon generation failed."
    exit 1
fi
