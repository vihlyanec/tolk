#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/takt-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
takt_developer=$(xcode-select -p)
if [[ -d "$takt_developer/Library/Developer/Frameworks/Testing.framework" ]]; then
    swift test --build-system native --disable-sandbox --cache-path "${TMPDIR:-/private/tmp}/takt-spm-cache" --scratch-path /private/tmp/takt-native \
        -Xswiftc -F -Xswiftc "$takt_developer/Library/Developer/Frameworks" \
        -Xswiftc -load-plugin-library -Xswiftc "$takt_developer/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
        -Xlinker -rpath -Xlinker "$takt_developer/Library/Developer/Frameworks"
else
    swift test --disable-sandbox --cache-path "${TMPDIR:-/private/tmp}/takt-spm-cache" --scratch-path /private/tmp/takt-tests
fi
