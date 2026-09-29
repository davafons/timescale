#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:?Usage: generate-appcast.sh VERSION}
private_key_file=${SPARKLE_PRIVATE_KEY_FILE:?Set SPARKLE_PRIVATE_KEY_FILE to the Sparkle private key file}
archive_name="Timescale-$version-macOS-universal.zip"
archive="$project_dir/dist/$archive_name"
tool="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/timescale-appcast.XXXXXX")

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

test -s "$archive"
test -s "$private_key_file"
test -x "$tool"

cp "$archive" "$staging_dir/$archive_name"
"$tool" \
    --ed-key-file "$private_key_file" \
    --download-url-prefix "https://github.com/davafons/timescale/releases/download/v$version/" \
    --maximum-deltas 0 \
    -o "$staging_dir/appcast.xml" \
    "$staging_dir"

cp "$staging_dir/appcast.xml" "$project_dir/dist/appcast.xml"
echo "$project_dir/dist/appcast.xml"
