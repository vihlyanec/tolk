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
widget_sources=("$PWD/Sources/TaktCore/WidgetData.swift" "$PWD/Sources/TaktWidget/TaskWidget.swift")
printf '%s\n' "$widget_sources[@]" > "$widget_path/sources.txt"
printf '%s\n' '["AppIntent","AppEntity","EntityQuery","WidgetConfigurationIntent","AppIntentsPackage"]' > "$widget_path/protocols.json"
printf '%s\n' "$widget_path/TaktWidget.swiftconstvalues" > "$widget_path/constants.txt"
widget_architectures=("$(uname -m)")
if [[ ${TOLK_UNIVERSAL:-0} == 1 ]]; then
    if [[ $widget_architectures[1] == arm64 ]]; then widget_architectures+=(x86_64); else widget_architectures+=(arm64); fi
fi
widget_target="$widget_architectures[1]-apple-macosx14.0"
widget_slices=()
for widget_architecture in "${widget_architectures[@]}"; do
    widget_flags=()
    if [[ $widget_architecture == $widget_architectures[1] ]]; then
        widget_flags=(-Xfrontend -emit-const-values-path -Xfrontend "$widget_path/TaktWidget.swiftconstvalues"
                      -Xfrontend -const-gather-protocols-file -Xfrontend "$widget_path/protocols.json")
    fi
    widget_slice="$widget_path/TaktWidget-$widget_architecture"
    "$widget_toolchain/usr/bin/swiftc" -sdk "$widget_sdk" -target "$widget_architecture-apple-macosx14.0" -application-extension \
        -swift-version 6 -parse-as-library -O -whole-module-optimization -module-name TaktWidget \
        -module-cache-path "${TMPDIR:-/private/tmp}/takt-widget-module-cache" \
        -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$widget_sdk_version" \
        "${widget_flags[@]}" "$widget_sources[@]" -o "$widget_slice"
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
"$widget_processor" --toolchain-dir "$widget_toolchain" --module-name TaktWidget --sdk-root "$widget_sdk" \
    --xcode-version "$widget_xcode_version" --platform-family macOS --deployment-target 14.0 \
    --target-triple "$widget_target" --source-file-list "$widget_path/sources.txt" \
    --swift-const-vals-list "$widget_path/constants.txt" --output "$widget_extension/Contents/Resources" --force
test -s "$widget_extension/Contents/Resources/Metadata.appintents/extract.actionsdata"
