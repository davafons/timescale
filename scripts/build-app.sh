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
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

if [ "${TIMESCALE_UNIVERSAL:-0}" = "1" ]; then
    arm_scratch="$project_dir/.build/universal-arm64"
    intel_scratch="$project_dir/.build/universal-x86_64"
    swift build -c release --triple arm64-apple-macosx14.0 --scratch-path "$arm_scratch"
    swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$intel_scratch"
    lipo -create \
        "$arm_scratch/arm64-apple-macosx/release/Timescale" \
        "$intel_scratch/x86_64-apple-macosx/release/Timescale" \
        -output "$contents_dir/MacOS/Timescale"
else
    swift build -c release
    cp "$project_dir/.build/release/Timescale" "$contents_dir/MacOS/Timescale"
fi

cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$project_dir/Resources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"

if [ "$code_sign_identity" = "-" ]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --timestamp --sign "$code_sign_identity" "$app_dir"
fi

echo "$app_dir"
