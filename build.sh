#!/bin/bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <base_image>" >&2
    exit 1
fi

BASE_IMAGE="$1"
TARGET_IMAGE="${IMAGE_PREFIX:-dev}/$(echo "$BASE_IMAGE" | cut -d'/' -f2-)"

echo "BASE_IMAGE=$BASE_IMAGE"
echo "TARGET_IMAGE=$TARGET_IMAGE"

if [[ ! -f dockerfile ]]; then
    echo "Error: dockerfile not found in current directory" >&2
    exit 1
fi

docker build -f dockerfile \
    --progress=plain \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    -t "$TARGET_IMAGE" .
