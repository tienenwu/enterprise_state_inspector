#!/usr/bin/env bash
set -euo pipefail

JDK_DIR="$(cd "$(dirname "$0")"/.. && pwd)/.java"
JDK_VERSION="jdk-17.0.9+9"
ARCHIVE="OpenJDK17U-jdk_x64_mac_hotspot_17.0.9_9.tar.gz"
DOWNLOAD_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/${ARCHIVE}"

mkdir -p "$JDK_DIR"

if [ -d "$JDK_DIR/$JDK_VERSION/Contents/Home" ]; then
  echo "JDK already present at $JDK_DIR/$JDK_VERSION"
  exit 0
fi

echo "Downloading Temurin 17 from $DOWNLOAD_URL"
TMP_ARCHIVE="$JDK_DIR/$ARCHIVE"
rm -f "$TMP_ARCHIVE"
curl -L "$DOWNLOAD_URL" -o "$TMP_ARCHIVE"

echo "Extracting..."
tar -xzf "$TMP_ARCHIVE" -C "$JDK_DIR"
rm -f "$TMP_ARCHIVE"

echo "JDK 17 available at $JDK_DIR/$JDK_VERSION/Contents/Home"
