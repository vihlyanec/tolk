#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/takt-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
tolk_scratch=${TOLK_SCRATCH_PATH:-/private/tmp/takt-native}
tolk_output=${TOLK_OUTPUT_DIR:-$PWD/build}
tolk_arch=()
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then tolk_arch=(--arch arm64 --arch x86_64); fi
swift build --build-system native --disable-sandbox --cache-path "${TMPDIR:-/private/tmp}/takt-spm-cache" --scratch-path "$tolk_scratch" "${tolk_arch[@]}" -c release
takt_binary_dir=$(swift build --build-system native --disable-sandbox --cache-path "${TMPDIR:-/private/tmp}/takt-spm-cache" --scratch-path "$tolk_scratch" "${tolk_arch[@]}" -c release --show-bin-path)
takt_stage_dir=$(mktemp -d /private/tmp/takt-package.XXXXXX)
trap 'rm -rf "$takt_stage_dir"' EXIT
mkdir -p "$tolk_output"
tolk_variants=("Толк" "Толк Demo")
if [[ ${TOLK_RELEASE:-0} == 1 ]]; then tolk_variants=("Толк"); fi
if [[ ${TOLK_SYNC_TEST:-0} == 1 ]]; then
    if [[ ${TOLK_RELEASE:-0} == 1 ]]; then print -u2 "Sync Test не может быть релизом"; exit 1; fi
    tolk_variants=("Толк Sync Test")
fi
for takt_variant in "${tolk_variants[@]}"; do
    takt_bundle="$takt_stage_dir/$takt_variant.app"
    mkdir -p "$takt_bundle/Contents/MacOS" "$takt_bundle/Contents/Resources" "$takt_bundle/Contents/Frameworks"
    cp "$takt_binary_dir/Takt" "$takt_bundle/Contents/MacOS/Takt"
    cp Resources/Info.plist "$takt_bundle/Contents/Info.plist"
    cp Resources/BrandIcon.png "$takt_bundle/Contents/Resources/BrandIcon.png"
    cp Resources/Completion.wav "$takt_bundle/Contents/Resources/Completion.wav"
    cp Resources/AppIcon.icns "$takt_bundle/Contents/Resources/AppIcon.icns"
    # ditto preserves the framework's symlinks and original nested signatures.
    ditto --norsrc "$takt_binary_dir/Sparkle.framework" "$takt_bundle/Contents/Frameworks/Sparkle.framework"
    cp "$tolk_scratch"/artifacts/*/Sparkle/LICENSE "$takt_bundle/Contents/Resources/Sparkle-LICENSE.txt"
    if [[ "$takt_variant" == "Толк Demo" ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.takt.demo' "$takt_bundle/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleName Толк Demo' "$takt_bundle/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Толк Demo' "$takt_bundle/Contents/Info.plist"
    fi
    if [[ "$takt_variant" == "Толк Sync Test" ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.takt.synctest' "$takt_bundle/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleName Толк Sync Test' "$takt_bundle/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Толк Sync Test' "$takt_bundle/Contents/Info.plist"
    fi
    tolk_config_args=()
    if [[ ${TOLK_RELEASE:-0} == 1 ]]; then tolk_config_args=(--release); fi
    python3 scripts/configure_bundle.py "$takt_bundle" "${tolk_config_args[@]}"
    codesign --force --sign - "$takt_bundle"
    codesign --verify --deep --strict "$takt_bundle"
    # Remove only the generated destination: ditto merges could retain obsolete app files.
    if [[ -d "$tolk_output/$takt_variant.app" ]]; then rm -rf "$tolk_output/$takt_variant.app"; fi
    ditto --norsrc "$takt_bundle" "$tolk_output/$takt_variant.app"
    # File Provider can attach Finder/resource-fork metadata during the destination copy.
    # Clear generated bundle metadata and verify the deliverable, not only the stage.
    xattr -cr "$tolk_output/$takt_variant.app"
    codesign --verify --deep --strict "$tolk_output/$takt_variant.app"
done
for takt_variant in "${tolk_variants[@]}"; do print "Готово: $tolk_output/$takt_variant.app"; done
