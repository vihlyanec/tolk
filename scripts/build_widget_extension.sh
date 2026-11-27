#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n ${TOLK_WIDGET_XCODE:-} ]]; then
    export DEVELOPER_DIR=$TOLK_WIDGET_XCODE
elif ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
widget_toolchain=$(xcrun --find swiftc)
widget_toolchain=${widget_toolchain:h:h:h}
widget_processor="$widget_toolchain/usr/bin/appintentsmetadataprocessor"
if [[ ! -x "$widget_processor" ]]; then
    print -u2 "Нужен полный Xcode для сборки метаданных App Intents."
    exit 1
fi
widget_sdk=$(xcrun --sdk macosx --show-sdk-path)
widget_sdk_version=$(xcrun --sdk "$widget_sdk" --show-sdk-version)
widget_xcode_version=$(xcodebuild -version | awk '/Build version/{print $3}')
widget_extension="$1/Contents/PlugIns/TaktWidget.appex"
widget_path="$(mktemp -d /private/tmp/tolk-widget-build.XXXXXX)"
trap 'rm -rf "$widget_path"' EXIT
mkdir -p "$widget_extension/Contents/MacOS" "$widget_extension/Contents/Resources"
cp Resources/Widget/Info.plist "$widget_extension/Contents/Info.plist"
widget_host_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $widget_host_id.tasks" "$widget_extension/Contents/Info.plist"
for widget_key in CFBundleShortVersionString CFBundleVersion; do
    widget_version=$(/usr/libexec/PlistBuddy -c "Print :$widget_key" "$1/Contents/Info.plist")
    /usr/libexec/PlistBuddy -c "Set :$widget_key $widget_version" "$widget_extension/Contents/Info.plist"
done
widget_intent_sources=("$PWD/Sources/TaktCore/WidgetData.swift" "$PWD/Sources/Takt/TaskWidgetIntents.swift")
widget_sources=("${widget_intent_sources[@]}" "$PWD/Sources/TaktWidget/TaskWidget.swift")
printf '%s\n' "$widget_sources[@]" > "$widget_path/sources.txt"
printf '%s\n' "$widget_intent_sources[@]" > "$widget_path/host-sources.txt"
printf '%s\n' '["AppIntent","AppEntity","EntityQuery","WidgetConfigurationIntent","AppIntentsPackage"]' > "$widget_path/protocols.json"
# Xcode 26 accepts the protocol list through the frontend, while the driver schedules the output.
widget_const_flags=(-emit-const-values -Xfrontend -const-gather-protocols-file -Xfrontend "$widget_path/protocols.json")
for widget_module in Takt TaktWidget; do
    printf '{"":{"const-values":"%s/%s.swiftconstvalues"}}\n' "$widget_path" "$widget_module" > "$widget_path/$widget_module.outputs.json"
done
widget_architectures=("$(uname -m)")
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then
    if [[ $widget_architectures[1] == arm64 ]]; then widget_architectures+=(x86_64); else widget_architectures+=(arm64); fi
fi
widget_target="$widget_architectures[1]-apple-macosx14.0"
widget_slices=()
for widget_architecture in "${widget_architectures[@]}"; do
    widget_flags=()
    if [[ $widget_architecture == $widget_architectures[1] ]]; then
        widget_flags=("${widget_const_flags[@]}"
                      -output-file-map "$widget_path/TaktWidget.outputs.json")
    fi
    widget_slice="$widget_path/TaktWidget-$widget_architecture"
    "$widget_toolchain/usr/bin/swiftc" -sdk "$widget_sdk" -target "$widget_architecture-apple-macosx14.0" -application-extension \
        -swift-version 6 -parse-as-library -O -whole-module-optimization -module-name TaktWidget -D TOLK_WIDGET_STANDALONE \
        -module-cache-path "${TMPDIR:-/private/tmp}/takt-widget-module-cache" \
        -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$widget_sdk_version" \
        -Xlinker -e -Xlinker _NSExtensionMain \
        "${widget_flags[@]}" "$widget_sources[@]" -o "$widget_slice"
    # Xcode starts macOS app extensions through Foundation while retaining the Swift widget entry.
    widget_symbols=$(nm -m "$widget_slice")
    if [[ "$widget_symbols" != *'external _NSExtensionMain (from Foundation)'* || "$widget_symbols"$'\n' != *'external _main'$'\n'* ]]; then
        print -u2 "В бинарнике виджета отсутствует точка входа расширения macOS ($widget_architecture)."
        exit 1
    fi
    widget_slices+=("$widget_slice")
done
widget_binary="$widget_extension/Contents/MacOS/TaktWidget"
widget_verify=()
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then
    lipo -create "${widget_slices[@]}" -output "$widget_binary"
    widget_verify=(--universal)
else
    mv "$widget_slices[1]" "$widget_binary"
fi
python3 scripts/verify_build_sdk.py "$widget_binary" --expected-sdk "$widget_sdk_version" "${widget_verify[@]}"

emit_intent_metadata() {
    local module=$1 binary=$2 bundle_id=$3 resources=$4 sources=$5
    printf '%s\n' "$widget_path/$module.swiftconstvalues" > "$widget_path/$module.constants.txt"
    "$widget_processor" --toolchain-dir "$widget_toolchain" --module-name "$module" --sdk-root "$widget_sdk" \
        --xcode-version "$widget_xcode_version" --platform-family macOS --deployment-target 14.0 \
        --target-triple "$widget_target" --bundle-identifier "$bundle_id" --binary-file "$binary" \
        --source-file-list "$sources" --swift-const-vals-list "$widget_path/$module.constants.txt" \
        --output "$resources" --compile-time-extraction --deployment-aware-processing
    test -s "$resources/Metadata.appintents/extract.actionsdata"
}

emit_intent_metadata TaktWidget "$widget_binary" "$widget_host_id.tasks" \
    "$widget_extension/Contents/Resources" "$widget_path/sources.txt"

# WidgetKit looks up the default intent by the containing app's bundle identifier.
"$widget_toolchain/usr/bin/swiftc" -sdk "$widget_sdk" -target "$widget_target" -c \
    -swift-version 6 -parse-as-library -O -whole-module-optimization -module-name Takt -D TOLK_WIDGET_STANDALONE \
    -module-cache-path "${TMPDIR:-/private/tmp}/takt-widget-module-cache" \
    "${widget_const_flags[@]}" \
    -output-file-map "$widget_path/Takt.outputs.json" \
    "${widget_intent_sources[@]}" -o "$widget_path/TaktIntents.o"
emit_intent_metadata Takt "$1/Contents/MacOS/Takt" "$widget_host_id" "$1/Contents/Resources" "$widget_path/host-sources.txt"
