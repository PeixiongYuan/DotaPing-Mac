# Sourced by build.sh and test.sh. Compiles with swiftc directly, so a
# damaged SwiftPM manifest API in the installed Command Line Tools cannot
# block the build. Needs only the Command Line Tools; no Xcode, no network.
BUILD="$PWD/.build/direct"
mkdir -p "$BUILD/modules" "$BUILD/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
SWIFTC=(xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos13.0"
        -swift-version 5 -module-cache-path "$BUILD/module-cache")
build_core() {
    "${SWIFTC[@]}" "$@" -parse-as-library -emit-library -static -module-name PingCore \
        -emit-module -emit-module-path "$BUILD/modules/PingCore.swiftmodule" \
        Sources/PingCore/*.swift -o "$BUILD/libPingCore.a"
}
