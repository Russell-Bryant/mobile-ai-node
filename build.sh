#!/bin/bash
# build.sh — Build llama.cpp with Vulkan support for Android Termux
# Run this on the phone via Termux
#
# IMPORTANT: Use the subshell background pattern to survive SSH disconnects:
#   (bash build.sh &)
#
# The build takes 20-30 minutes. SSH may crash during GPU shader compilation.

set -e

LLAMA_DIR="$HOME/llama.cpp"
STABLE_COMMIT="c20c44514"
BUILD_DIR="build_vk"

# Install dependencies
pkg install -y git cmake build-essential vulkan-loader-android mesa-vulkan-icd-freedreno

# Clone and checkout stable commit
if [ ! -d "$LLAMA_DIR" ]; then
  git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
fi

cd "$LLAMA_DIR"
git checkout "$STABLE_COMMIT"

# Clean build
rm -rf "$BUILD_DIR"
mkdir "$BUILD_DIR" && cd "$BUILD_DIR"

# Configure
cmake -DBUILD_SHARED_LIBS=OFF \
      -DGGML_VULKAN=ON \
      -DGGML_CPU=ON \
      ..

# Build (adjust -j flag based on your device)
cmake --build . --target llama-server -j$(nproc)

echo "Build complete: $LLAMA_DIR/$BUILD_DIR/bin/llama-server"
echo "File size: $(ls -lh $LLAMA_DIR/$BUILD_DIR/bin/llama-server | awk '{print $5}')"
