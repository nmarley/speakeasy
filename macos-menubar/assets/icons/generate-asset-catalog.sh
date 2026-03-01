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

# Clean up previous run
rm -fr ./Assets.xcassets

# Run the Docker container
echo "Generating icons using Docker"
docker run --rm \
    -v "$(pwd):/app" \
    "$DOCKER_IMAGE_NAME" "$SVG_FILENAME"

# Check if the Assets.xcassets directory was created
if [ -d "Assets.xcassets" ]; then
    # Move the Assets.xcassets directory to the Resources directory
    # echo "Moving Assets.xcassets to ${RESOURCES_DIR}/"
    # rm -rf "${RESOURCES_DIR}/Assets.xcassets"
    # mv Assets.xcassets "${RESOURCES_DIR}/"
    echo "Icon generation complete! Assets catalog is at ./Assets.xcassets"
    echo "Please move the Assets.xcassets directory to your project Resources folder"
else
    echo "Error: Icon generation failed."
    exit 1
fi
