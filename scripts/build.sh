#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/compile.sh
build_core -O
"${SWIFTC[@]}" -O -module-name DotaPing -I "$BUILD/modules" -L "$BUILD" -lPingCore Sources/DotaPing/*.swift -o "$BUILD/DotaPing"
APP="$PWD/dist/DotaPing.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/DotaPing" "$APP/Contents/MacOS/DotaPing"
cp Resources/Info.plist "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/Resources/Sounds"
cp -R Resources/Sounds "$APP/Contents/Resources/"
cp Resources/asset-sources.json "$APP/Contents/Resources/"
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" || scripts/make_icon.swift -nt "$APP/Contents/Resources/AppIcon.icns" ]]; then
    rm -rf "$BUILD/AppIcon.iconset"
    "${SWIFTC[@]}" scripts/make_icon.swift -o "$BUILD/make_icon"
    "$BUILD/make_icon" "$BUILD/AppIcon.iconset"
    iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi
source scripts/signing.sh
ensure_signing_identity
codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KEYCHAIN" --identifier local.dotaping.DotaPing --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/DotaPing" --check-assets
print "Built: $APP"
