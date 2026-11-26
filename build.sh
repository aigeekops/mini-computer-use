#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

target=".build/Mini Computer Use Target.app"
mkdir -p "$target/Contents/MacOS"
cp Sources/Target-Info.plist "$target/Contents/Info.plist"
sdk_target="$(uname -m)-apple-macos14.0"
xcrun swiftc -module-cache-path .build/module-cache -parse-as-library -target "$sdk_target" Sources/Target.swift -o "$target/Contents/MacOS/Target"
xcrun swiftc -module-cache-path .build/module-cache -parse-as-library -target "$sdk_target" Sources/MiniComputerUse.swift -o .build/mini-computer-use
