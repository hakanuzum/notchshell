#!/usr/bin/env bash
set -euo pipefail

# Build GhosttyKit.xcframework from the vendored ghostty submodule.
# Uses SHA-based caching to skip rebuilds when the submodule hasn't changed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"
XCFRAMEWORK_DIR="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
CACHE_FILE="$PROJECT_ROOT/.ghostty-build-sha"

if [ ! -d "$GHOSTTY_DIR/.git" ] && [ ! -f "$GHOSTTY_DIR/.git" ]; then
    echo "Error: vendor/ghostty submodule not found."
    echo "Run: git submodule update --init vendor/ghostty"
    exit 1
fi

ZIG_015="$(brew --prefix zig@0.15 2>/dev/null)/bin/zig"
if [ -x "$ZIG_015" ]; then
    export PATH="$(dirname "$ZIG_015"):$PATH"
elif ! command -v zig &>/dev/null; then
    echo "Error: zig 0.15.x not found. Install with: brew install zig@0.15"
    exit 1
fi

# Get current submodule SHA
CURRENT_SHA=$(cd "$GHOSTTY_DIR" && git rev-parse HEAD)

# Check cache
if [ -f "$CACHE_FILE" ] && [ -d "$XCFRAMEWORK_DIR" ]; then
    CACHED_SHA=$(cat "$CACHE_FILE")
    if [ "$CURRENT_SHA" = "$CACHED_SHA" ]; then
        echo "GhosttyKit.xcframework is up to date (SHA: ${CURRENT_SHA:0:12})"
        exit 0
    fi
fi

TARGET_FLAG="-Dxcframework-target=native"
if [ "${1:-}" = "--universal" ]; then
    TARGET_FLAG=""
    echo "Building GhosttyKit.xcframework [universal] (SHA: ${CURRENT_SHA:0:12})..."
else
    echo "Building GhosttyKit.xcframework [native] (SHA: ${CURRENT_SHA:0:12})..."
fi

cd "$GHOSTTY_DIR"

# Remove stale xcframework if it exists (xcodebuild -create-xcframework fails if output exists)
rm -rf "$XCFRAMEWORK_DIR"

# Build under a neutral cache path. Ghostty's C dependencies bake __FILE__ into
# assertion messages, so whoever builds leaves their home directory inside the
# shipped binary — the prebuilt library we used to link carried the original
# author's username for exactly this reason. Pointing the cache somewhere
# anonymous means the paths that survive identify nobody.
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-/private/tmp/notchshell-zig-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-/private/tmp/notchshell-zig-cache/local}"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
echo "Zig cache: $ZIG_GLOBAL_CACHE_DIR"

zig build -Demit-xcframework=true -Demit-macos-app=false -Doptimize=ReleaseFast $TARGET_FLAG

if [ ! -d "$XCFRAMEWORK_DIR" ]; then
    echo "Error: xcframework not found at $XCFRAMEWORK_DIR after build."
    exit 1
fi

# Xcode 26 libtool (cctools_ld-1267) silently drops .o files that aren't
# 8-byte aligned; zig 0.15.x emits misaligned objects. Rebuild each
# platform library from the intermediate .a files using ar (no alignment check).

# Helper: rebuild a single-arch .a from zig-cache archives
# $1 = target arch (arm64/x86_64, empty = any)
# $2 = output .a file
# $3 = target platform numeric (1=MACOS, 2=IOS, 7=IOSSIMULATOR, empty = any)
rebuild_from_cache() {
    local target_arch="$1"
    local out_file="$2"
    local target_platform="$3"
    local merge_dir
    merge_dir=$(mktemp -d)

    for archive in "$GHOSTTY_DIR"/.zig-cache/o/*/lib*.a; do
        [ -f "$archive" ] || continue
        base=$(basename "$archive")
        [ "$base" = "libghostty-fat.a" ] && continue
        echo "$base" | grep -q "libghostty-vt" && continue
        # Skip fat (multi-arch) files — ar can't extract them
        arch_count=$(lipo -info "$archive" 2>/dev/null | grep -oE 'arm64|x86_64' | wc -l | tr -d ' ')
        [ "$arch_count" -gt 1 ] && continue
        # Filter by architecture
        if [ -n "$target_arch" ]; then
            file_arch=$(lipo -info "$archive" 2>/dev/null | grep -oE 'arm64|x86_64' | head -1 || true)
            [ "$file_arch" = "$target_arch" ] || continue
        fi
        # Filter by platform via LC_BUILD_VERSION (1=MACOS, 2=IOS, 7=IOSSIMULATOR)
        if [ -n "$target_platform" ]; then
            file_platform=$( (otool -l "$archive" 2>/dev/null || true) | awk '/^ *platform /{print $2; exit}' )
            [ -z "$file_platform" ] && continue
            [ "$file_platform" = "$target_platform" ] || continue
        fi
        SUB=$(mktemp -d)
        (cd "$SUB" && ar x "$archive" && chmod 644 *.o 2>/dev/null || true)
        local prefix="${base%.a}_"
        for obj in "$SUB"/*.o; do
            [ -f "$obj" ] || continue
            name="${prefix}$(basename "$obj")"
            [ ! -f "$merge_dir/$name" ] && mv "$obj" "$merge_dir/$name"
        done
        rm -rf "$SUB"
    done

    local obj_count
    obj_count=$(ls "$merge_dir"/*.o 2>/dev/null | wc -l | tr -d ' ')
    if [ "$obj_count" -eq 0 ]; then
        echo "    ${target_arch:-all} ($target_platform): WARNING no objects found"
        rm -rf "$merge_dir"
        return 1
    fi
    ar rcs "$out_file" "$merge_dir"/*.o
    ranlib "$out_file"
    rm -rf "$merge_dir"
    echo "    ${target_arch:-all} ($target_platform): $obj_count objects"
}

# Remove iOS slices — notchshell is macOS only, and iOS objects
# would contaminate the macOS library during rebuild
for ios_dir in "$XCFRAMEWORK_DIR"/ios-*/; do
    [ -d "$ios_dir" ] || continue
    echo "Removing $(basename "$ios_dir") (macOS-only project)..."
    rm -rf "$ios_dir"
done
# Rewrite Info.plist to only contain the macOS library
PLIST="$XCFRAMEWORK_DIR/Info.plist"
MACOS_DIR=$(ls -d "$XCFRAMEWORK_DIR"/macos-* 2>/dev/null | head -1)
if [ -n "$MACOS_DIR" ]; then
    MACOS_ID=$(basename "$MACOS_DIR")
    LIB_FILE=$(ls "$MACOS_DIR"/*.a 2>/dev/null | head -1)
    LIB_NAME=$(basename "$LIB_FILE")
    ARCHS=$(lipo -info "$LIB_FILE" 2>/dev/null | grep -oE 'arm64|x86_64' | sort -u || true)
    ARCH_XML=""
    for a in $ARCHS; do
        ARCH_XML="$ARCH_XML<string>$a</string>"
    done
    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key>
			<string>$LIB_NAME</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>$MACOS_ID</string>
			<key>LibraryPath</key>
			<string>$LIB_NAME</string>
			<key>SupportedArchitectures</key>
			<array>
				$ARCH_XML
			</array>
			<key>SupportedPlatform</key>
			<string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLISTEOF
fi

for lib_dir in "$XCFRAMEWORK_DIR"/*/; do
    dir_name=$(basename "$lib_dir")

    # Handle single-arch libghostty-fat.a
    fat_lib="$lib_dir/libghostty-fat.a"
    if [ -f "$fat_lib" ]; then
        sym_count=$(nm "$fat_lib" 2>/dev/null | grep -c " T _ghostty_app_new" || true)
        if [ "$sym_count" -eq 0 ]; then
            echo "Rebuilding $dir_name/libghostty-fat.a (libtool dropped misaligned objects)..."
            rebuild_from_cache "" "$fat_lib" "1"
            ghostty_syms=$(nm "$fat_lib" 2>/dev/null | grep -c ' T _ghostty' || echo 0)
            echo "  Done: $ghostty_syms ghostty symbols"
        fi
    fi

    # Handle universal lipo'd libghostty.a
    lipo_lib="$lib_dir/libghostty.a"
    if [ -f "$lipo_lib" ]; then
        sym_count=$(nm "$lipo_lib" 2>/dev/null | grep -c " T _ghostty_app_new" || true)
        if [ "$sym_count" -eq 0 ]; then
            echo "Rebuilding $dir_name/libghostty.a (libtool dropped misaligned objects)..."
            WORK_DIR=$(mktemp -d)
            archs=$(lipo -info "$lipo_lib" 2>/dev/null | grep -oE 'arm64|x86_64' | sort -u || true)
            for arch in $archs; do
                rebuild_from_cache "$arch" "$WORK_DIR/lib-$arch.a" "1"
            done
            lipo_args=""
            for arch in $archs; do
                lipo_args="$lipo_args $WORK_DIR/lib-$arch.a"
            done
            lipo -create $lipo_args -output "$lipo_lib"
            rm -rf "$WORK_DIR"
            ghostty_syms=$(nm "$lipo_lib" 2>/dev/null | grep -c ' T _ghostty' || echo 0)
            echo "  Done: $ghostty_syms ghostty symbols"
        fi
    fi
done

echo "$CURRENT_SHA" > "$CACHE_FILE"
echo "Build complete: $XCFRAMEWORK_DIR"
