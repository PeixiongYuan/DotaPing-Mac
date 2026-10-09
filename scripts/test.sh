#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/compile.sh
build_core
"${SWIFTC[@]}" -parse-as-library -module-name PingCoreChecks -I "$BUILD/modules" -L "$BUILD" -lPingCore Tests/PingCoreTests/*.swift -o "$BUILD/PingCoreChecks"
"$BUILD/PingCoreChecks"
