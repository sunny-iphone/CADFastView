#!/usr/bin/env bash
set -euo pipefail

mkdir -p Vendor
if [ -d "Vendor/libdxfrw" ]; then
  echo "Vendor/libdxfrw already exists. Pulling latest..."
  git -C Vendor/libdxfrw pull --ff-only
else
  git clone --depth 1 https://github.com/LibreCAD/libdxfrw.git Vendor/libdxfrw
fi

echo "Done! See README.md for Xcode Build Settings (USE_LIBDXFRW=1)."
