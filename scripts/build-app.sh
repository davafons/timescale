#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/build/Timescale.app"
contents_dir="$app_dir/Contents"
version=${TIMESCALE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")}
build_number=${TIMESCALE_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$project_dir/Resources/Info.plist")}
code_sign_identity=${CODE_SIGN_IDENTITY:--}

cd "$project_dir"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$contents_dir/Frameworks"

if [ "${TIMESCALE_UNIVERSAL:-0}" = "1" ]; then
    arm_scratch="$project_dir/.build/universal-arm64"
    intel_scratch="$project_dir/.build/universal-x86_64"
    swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$arm_scratch"
    swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$intel_scratch"
    lipo -create \
        "$arm_scratch/release/Timescale" \
        "$intel_scratch/release/Timescale" \
        -output "$contents_dir/MacOS/Timescale"
    sparkle_framework="$arm_scratch/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
else
    swift build -c release
    cp "$project_dir/.build/release/Timescale" "$contents_dir/MacOS/Timescale"
    sparkle_framework="$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi

ditto "$sparkle_framework" "$contents_dir/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$contents_dir/MacOS/Timescale"

cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$project_dir/Resources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"

if [ "$code_sign_identity" = "-" ]; then
    codesign --force --deep --sign - "$app_dir"
else
    sparkle_bundle="$contents_dir/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$code_sign_identity" \
        "$sparkle_bundle/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
        --sign "$code_sign_identity" "$sparkle_bundle/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "$code_sign_identity" \
        "$sparkle_bundle/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$code_sign_identity" \
        "$sparkle_bundle/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp --sign "$code_sign_identity" "$sparkle_bundle"
    codesign --force --options runtime --timestamp --sign "$code_sign_identity" "$app_dir"
fi

echo "$app_dir"
