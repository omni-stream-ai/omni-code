#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -q
sudo apt-get install -y \
  clang cmake ninja-build pkg-config default-jdk-headless \
  libasound2-dev libpulse-dev libgtk-3-dev libepoxy-dev \
  liblz4-1 libgl1 libgbm1 libdrm2 libx11-xcb1 \
  libwebkit2gtk-4.1-dev liblzma-dev libcurl4-openssl-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  patchelf binutils dpkg-dev desktop-file-utils python3 curl file
