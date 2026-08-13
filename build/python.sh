#!/bin/bash
set -e

VERSION=$1
TARGET=$2

if [ -z "$VERSION" ] || [ -z "$TARGET" ]; then
    echo "Usage: $0 <version> <target>"
    exit 1
fi

echo "Building Python $VERSION for $TARGET..."

OUT_DIR="runtime/python/$VERSION/$TARGET"
mkdir -p "$OUT_DIR"

# For Desktop, we use indygreg/python-build-standalone
# For simplicity, we hardcode a stable release for 3.12.x series.
PYTHON_BUILD_TAG="20240726"
PYTHON_VER="3.12.4"
# If user requests a different version, we can map it, but default is 3.12.4
if [[ "$VERSION" == *"3.12"* ]]; then
    PYTHON_VER="3.12.4"
    PYTHON_BUILD_TAG="20240726"
fi

BASE_URL="https://github.com/indygreg/python-build-standalone/releases/download/$PYTHON_BUILD_TAG"

case "$TARGET" in
  "linux-x64")
    PY_FILE="cpython-${PYTHON_VER}+${PYTHON_BUILD_TAG}-x86_64-unknown-linux-gnu-install_only.tar.gz"
    echo "Downloading $PY_FILE..."
    curl -L -o "$PY_FILE" "$BASE_URL/$PY_FILE"
    tar -xzf "$PY_FILE"
    mv python "$OUT_DIR/"
    rm -f "$PY_FILE"
    ;;
  "linux-arm64")
    PY_FILE="cpython-${PYTHON_VER}+${PYTHON_BUILD_TAG}-aarch64-unknown-linux-gnu-install_only.tar.gz"
    echo "Downloading $PY_FILE..."
    curl -L -o "$PY_FILE" "$BASE_URL/$PY_FILE"
    tar -xzf "$PY_FILE"
    mv python "$OUT_DIR/"
    rm -f "$PY_FILE"
    ;;
  "macos-x64")
    PY_FILE="cpython-${PYTHON_VER}+${PYTHON_BUILD_TAG}-x86_64-apple-darwin-install_only.tar.gz"
    echo "Downloading $PY_FILE..."
    curl -L -o "$PY_FILE" "$BASE_URL/$PY_FILE"
    tar -xzf "$PY_FILE"
    mv python "$OUT_DIR/"
    rm -f "$PY_FILE"
    ;;
  "macos-arm64")
    PY_FILE="cpython-${PYTHON_VER}+${PYTHON_BUILD_TAG}-aarch64-apple-darwin-install_only.tar.gz"
    echo "Downloading $PY_FILE..."
    curl -L -o "$PY_FILE" "$BASE_URL/$PY_FILE"
    tar -xzf "$PY_FILE"
    mv python "$OUT_DIR/"
    rm -f "$PY_FILE"
    ;;
  "windows-x64")
    PY_FILE="cpython-${PYTHON_VER}+${PYTHON_BUILD_TAG}-x86_64-pc-windows-msvc-shared-install_only.tar.gz"
    echo "Downloading $PY_FILE..."
    curl -L -o "$PY_FILE" "$BASE_URL/$PY_FILE"
    tar -xzf "$PY_FILE"
    mv python "$OUT_DIR/"
    rm -f "$PY_FILE"
    ;;
  "android-arm64-v8a")
    ANDROID_ARCH="aarch64"
    echo "Downloading Android Python and dependencies from Termux..."
    mkdir -p tmp_android && cd tmp_android
    
    echo "Fetching Termux Packages index..."
    curl -f -s -L -o Packages "https://grimler.se/termux/termux-main/dists/stable/main/binary-$ANDROID_ARCH/Packages"
    
    PKGS="python libandroid-support libffi openssl libbz2 libsqlite liblzma zlib libgdbm libcrypt ncurses readline ca-certificates"
    
    for PKG in $PKGS; do
        FILENAME=$(grep -A 20 "^Package: $PKG\$" Packages | grep "^Filename: " | head -n 1 | awk '{print $2}')
        if [ -n "$FILENAME" ]; then
            echo "Downloading $PKG..."
            curl -f -s -L -o "$PKG.deb" "https://grimler.se/termux/termux-main/$FILENAME"
            
            ar x "$PKG.deb" 2>/dev/null || true
            tar -xf data.tar.xz 2>/dev/null || tar -xf data.tar.gz 2>/dev/null || echo "Failed to extract $PKG data"
            rm -f "$PKG.deb" data.tar.* control.tar.* debian-binary
        else
            echo "Warning: Package $PKG not found in Termux repo"
        fi
    done
    cd ..
    
    mkdir -p "$OUT_DIR/python/lib"
    mkdir -p "$OUT_DIR/python/bin"
    
    if [ -f "tmp_android/data/data/com.termux/files/usr/bin/python" ]; then
        cp -a tmp_android/data/data/com.termux/files/usr/bin/python* "$OUT_DIR/python/bin/"
    else
        echo "Error: python binary not found!"
        exit 1
    fi
    
    if [ -d "tmp_android/data/data/com.termux/files/usr/lib" ]; then
        cp -a tmp_android/data/data/com.termux/files/usr/lib/*.so* "$OUT_DIR/python/lib/" 2>/dev/null || true
        cp -a tmp_android/data/data/com.termux/files/usr/lib/python3.* "$OUT_DIR/python/lib/" 2>/dev/null || true
    fi
    
    rm -rf tmp_android
    
    cat << 'EOF' > "$OUT_DIR/python/bin/python_wrapper"
#!/system/bin/sh
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export HOME="$DIR"
export TMPDIR="$DIR/tmp"
mkdir -p "$TMPDIR"
export PYTHONHOME="$DIR"
export PYTHONPATH="$DIR/lib/python3.11" # Update this based on termux version if needed

if [ -f "/system/bin/linker64" ] && [ -f "$DIR/bin/python3" ]; then
    export LD_LIBRARY_PATH="$DIR/lib:$LD_LIBRARY_PATH"
    exec /system/bin/linker64 "$DIR/bin/python3" "$@"
else
    export LD_LIBRARY_PATH="$DIR/lib:$LD_LIBRARY_PATH"
    exec "$DIR/bin/python3" "$@"
fi
EOF
    chmod +x "$OUT_DIR/python/bin/python_wrapper"
    ;;
  *)
    echo "Unknown target: $TARGET"
    exit 1
    ;;
esac

echo "Python build complete."
