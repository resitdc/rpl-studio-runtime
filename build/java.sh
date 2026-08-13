#!/bin/bash
set -e

VERSION=$1
TARGET=$2

if [ -z "$VERSION" ] || [ -z "$TARGET" ]; then
    echo "Usage: $0 <version> <target>"
    exit 1
fi

echo "Building Java $VERSION for $TARGET..."

OUT_DIR="runtime/java/$VERSION/$TARGET"
mkdir -p "$OUT_DIR"

JAVA_VER="21"
if [[ "$VERSION" == *"21"* ]]; then
    JAVA_VER="21"
elif [[ "$VERSION" == *"17"* ]]; then
    JAVA_VER="17"
fi

BASE_URL="https://api.adoptium.net/v3/binary/latest/$JAVA_VER/ga"

case "$TARGET" in
  "linux-x64")
    echo "Downloading Java for Linux x64..."
    curl -L -o "java.tar.gz" "$BASE_URL/linux/x64/jre/hotspot/normal/eclipse?project=jdk"
    tar -xzf "java.tar.gz"
    mv jdk*/* "$OUT_DIR/"
    rm -rf jdk* java.tar.gz
    ;;
  "linux-arm64")
    echo "Downloading Java for Linux arm64..."
    curl -L -o "java.tar.gz" "$BASE_URL/linux/aarch64/jre/hotspot/normal/eclipse?project=jdk"
    tar -xzf "java.tar.gz"
    mv jdk*/* "$OUT_DIR/"
    rm -rf jdk* java.tar.gz
    ;;
  "macos-x64")
    echo "Downloading Java for macOS x64..."
    curl -L -o "java.tar.gz" "$BASE_URL/mac/x64/jre/hotspot/normal/eclipse?project=jdk"
    tar -xzf "java.tar.gz"
    mv jdk*/Contents/Home/* "$OUT_DIR/"
    rm -rf jdk* java.tar.gz
    ;;
  "macos-arm64")
    echo "Downloading Java for macOS arm64..."
    curl -L -o "java.tar.gz" "$BASE_URL/mac/aarch64/jre/hotspot/normal/eclipse?project=jdk"
    tar -xzf "java.tar.gz"
    mv jdk*/Contents/Home/* "$OUT_DIR/"
    rm -rf jdk* java.tar.gz
    ;;
  "windows-x64")
    echo "Downloading Java for Windows x64..."
    curl -L -o "java.zip" "$BASE_URL/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
    unzip -q "java.zip"
    mv jdk*/* "$OUT_DIR/"
    rm -rf jdk* java.zip
    ;;
  "android-arm64-v8a")
    ANDROID_ARCH="aarch64"
    echo "Downloading Android Java and dependencies from Termux..."
    mkdir -p tmp_android && cd tmp_android
    
    echo "Fetching Termux Packages index..."
    curl -f -s -L -o Packages "https://grimler.se/termux/termux-main/dists/stable/main/binary-$ANDROID_ARCH/Packages"
    
    PKGS="openjdk-17 libandroid-shmem libandroid-spawn littlecms alsa-plugins libandroid-support libffi openssl libbz2 libsqlite liblzma zlib libgdbm libcrypt ncurses readline ca-certificates freetype giflib libiconv libjpeg-turbo libpng libwebp xorgproto"
    
    for PKG in $PKGS; do
        FILENAME=$(grep -A 20 "^Package: $PKG\$" Packages | grep "^Filename: " | head -n 1 | awk '{print $2}')
        if [ -n "$FILENAME" ]; then
            echo "Downloading $PKG..."
            curl -f -L --retry 3 --retry-all-errors -o "$PKG.deb" "https://grimler.se/termux/termux-main/$FILENAME" || { echo "Failed to download $PKG"; exit 1; }
            
            ar x "$PKG.deb" 2>/dev/null || true
            tar -xf data.tar.xz 2>/dev/null || tar -xf data.tar.gz 2>/dev/null || echo "Failed to extract $PKG data"
            rm -f "$PKG.deb" data.tar.* control.tar.* debian-binary
        else
            echo "Warning: Package $PKG not found in Termux repo"
        fi
    done
    cd ..
    
    mkdir -p "$OUT_DIR/lib"
    mkdir -p "$OUT_DIR/bin"
    mkdir -p "$OUT_DIR/jvm"
    
    if [ -d "tmp_android/data/data/com.termux/files/usr/lib/jvm/openjdk-17" ]; then
        cp -a tmp_android/data/data/com.termux/files/usr/lib/jvm/openjdk-17/* "$OUT_DIR/jvm/"
    else
        echo "Error: openjdk-17 not found!"
        exit 1
    fi
    
    if [ -d "tmp_android/data/data/com.termux/files/usr/lib" ]; then
        cp -a tmp_android/data/data/com.termux/files/usr/lib/*.so* "$OUT_DIR/lib/" 2>/dev/null || true
    fi
    
    rm -rf tmp_android
    
    cat << 'EOF' > "$OUT_DIR/bin/java_wrapper"
#!/system/bin/sh
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export HOME="$DIR"
export TMPDIR="$DIR/tmp"
mkdir -p "$TMPDIR"
export JAVA_HOME="$DIR/jvm"

if [ -f "/system/bin/linker64" ] && [ -f "$JAVA_HOME/bin/java" ]; then
    export LD_LIBRARY_PATH="$DIR/lib:$JAVA_HOME/lib:$JAVA_HOME/lib/server:$LD_LIBRARY_PATH"
    exec /system/bin/linker64 "$JAVA_HOME/bin/java" "$@"
else
    export LD_LIBRARY_PATH="$DIR/lib:$JAVA_HOME/lib:$JAVA_HOME/lib/server:$LD_LIBRARY_PATH"
    exec "$JAVA_HOME/bin/java" "$@"
fi
EOF
    chmod +x "$OUT_DIR/bin/java_wrapper"
    ;;
  *)
    echo "Unknown target: $TARGET"
    exit 1
    ;;
esac

echo "Java build complete."
