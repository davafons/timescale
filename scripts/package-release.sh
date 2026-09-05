#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")}
build_number=${TIMESCALE_BUILD_NUMBER:-1}
artifact_name="Timescale-$version-macOS-universal"
dist_dir="$project_dir/dist"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/timescale-release.XXXXXX")

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

TIMESCALE_VERSION="$version" \
TIMESCALE_BUILD_NUMBER="$build_number" \
TIMESCALE_UNIVERSAL=1 \
"$project_dir/scripts/build-app.sh"

rm -rf "$dist_dir"
mkdir -p "$dist_dir" "$staging_dir/dmg"

ditto -c -k --sequesterRsrc --keepParent \
    "$project_dir/build/Timescale.app" \
    "$dist_dir/$artifact_name.zip"

ditto "$project_dir/build/Timescale.app" "$staging_dir/dmg/Timescale.app"
ln -s /Applications "$staging_dir/dmg/Applications"
hdiutil create \
    -volname "Timescale $version" \
    -srcfolder "$staging_dir/dmg" \
    -ov -format UDZO \
    "$dist_dir/$artifact_name.dmg"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$dist_dir/$artifact_name.dmg" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dist_dir/$artifact_name.dmg"
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$dist_dir/$artifact_name.dmg" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
    xcrun stapler staple "$dist_dir/$artifact_name.dmg"
fi

(
    cd "$dist_dir"
    shasum -a 256 "$artifact_name.zip" "$artifact_name.dmg" > SHA256SUMS
)

echo "Release artifacts:"
echo "$dist_dir/$artifact_name.zip"
echo "$dist_dir/$artifact_name.dmg"
echo "$dist_dir/SHA256SUMS"
