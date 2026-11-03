#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/takt-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
tolk_scratch=${TOLK_SCRATCH_PATH:-/private/tmp/takt-native}
tolk_output=${TOLK_OUTPUT_DIR:-$PWD/build}
# A multi-architecture SwiftPM invocation uses a different build backend, which
# can label the binary with the deployment target as its SDK (14.0). Build each
# slice through the same native path as Demo, then merge without rewriting SDKs.
tolk_sdk=$(xcrun --sdk macosx --show-sdk-path)
tolk_sdk_version=$(xcrun --sdk "$tolk_sdk" --show-sdk-version)
tolk_architectures=("$(uname -m)")
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then tolk_architectures=(arm64 x86_64); fi
takt_stage_dir=$(mktemp -d /private/tmp/takt-package.XXXXXX)
trap 'rm -rf "$takt_stage_dir"' EXIT
tolk_slices=()
takt_binary_dir=""
for tolk_architecture in "${tolk_architectures[@]}"; do
    tolk_build_args=(--build-system native --disable-sandbox --cache-path "${TMPDIR:-/private/tmp}/takt-spm-cache" --scratch-path "$tolk_scratch" --sdk "$tolk_sdk" --arch "$tolk_architecture" -c release)
    swift build "${tolk_build_args[@]}"
    tolk_slice_dir=$(swift build "${tolk_build_args[@]}" --show-bin-path)
    python3 scripts/verify_build_sdk.py "$tolk_slice_dir/Takt" --expected-sdk "$tolk_sdk_version"
    tolk_slices+=("$tolk_slice_dir/Takt")
    if [[ -z "$takt_binary_dir" ]]; then takt_binary_dir="$tolk_slice_dir"; fi
done
tolk_binary="$takt_stage_dir/Takt"
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then
    lipo -create "${tolk_slices[@]}" -output "$tolk_binary"
else
    cp "${tolk_slices[1]}" "$tolk_binary"
fi
tolk_verify_args=()
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then tolk_verify_args=(--universal); fi
python3 scripts/verify_build_sdk.py "$tolk_binary" --expected-sdk "$tolk_sdk_version" "${tolk_verify_args[@]}"
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
    cp "$tolk_binary" "$takt_bundle/Contents/MacOS/Takt"
    cp Resources/Info.plist "$takt_bundle/Contents/Info.plist"
    cp Resources/BrandIcon.png "$takt_bundle/Contents/Resources/BrandIcon.png"
    cp Resources/Completion.wav "$takt_bundle/Contents/Resources/Completion.wav"
    cp Resources/AppIcon.icns "$takt_bundle/Contents/Resources/TolkAppIcon.icns"
    # ditto preserves the framework's symlinks and original nested signatures.
    ditto --norsrc "$takt_binary_dir/Sparkle.framework" "$takt_bundle/Contents/Frameworks/Sparkle.framework"
    # SwiftPM can retain both extraction and final artifact directories.
    # Copy one license rather than passing several source files to a file target.
    tolk_license_files=("$tolk_scratch"/artifacts/*/Sparkle/LICENSE)
    cp "${tolk_license_files[1]}" "$takt_bundle/Contents/Resources/Sparkle-LICENSE.txt"
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
    tolk_sign_args=()
    if [[ ${TOLK_RELEASE:-0} == 1 && ${TOLK_TEST_BUILD:-0} != 1 ]]; then tolk_sign_args=(--release); fi
    python3 scripts/sign_bundle.py "$takt_bundle" "${tolk_sign_args[@]}"
    # Remove only the generated destination: ditto merges could retain obsolete app files.
    if [[ -d "$tolk_output/$takt_variant.app" ]]; then rm -rf "$tolk_output/$takt_variant.app"; fi
    ditto --norsrc "$takt_bundle" "$tolk_output/$takt_variant.app"
    # File Provider can attach Finder/resource-fork metadata during the destination copy.
    # Clear generated bundle metadata and verify the deliverable, not only the stage.
    xattr -cr "$tolk_output/$takt_variant.app"
    codesign --verify --deep --strict "$tolk_output/$takt_variant.app"
done
for takt_variant in "${tolk_variants[@]}"; do print "Готово: $tolk_output/$takt_variant.app"; done
