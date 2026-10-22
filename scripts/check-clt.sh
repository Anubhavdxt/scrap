#!/bin/sh
# Type-checks the whole app with only the Command Line Tools' compiler and SDK, the way a Mac without Xcode builds it.
# SwiftUI macros (such as @State on the macOS 27 SDK) come with Xcode only, so using one fails here.
set -e
CLT=/Library/Developer/CommandLineTools
SDK=$(ls -d "$CLT"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V | tail -1)
if [ ! -x "$CLT/usr/bin/swiftc" ] || [ -z "$SDK" ]; then echo "no Command Line Tools here: skipped"; exit 0; fi
OUT=$(mktemp -d)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$CLT/usr/bin/swiftc" -emit-module -parse-as-library -module-name ScrapCore -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" \
    "$ROOT"/Sources/ScrapCore/*.swift -o "$OUT/ScrapCore.swiftmodule" 2>&1 | grep -v "warning:" || true
"$CLT/usr/bin/swiftc" -typecheck -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK" -I "$OUT" "$ROOT"/Sources/ScrapApp/*.swift > "$OUT/app.log" 2>&1 || { grep "error:" "$OUT/app.log"; echo "the app does not build with only the Command Line Tools (SDK: $SDK)"; exit 1; }
echo "builds with only the Command Line Tools (SDK: $(basename "$SDK"))"
