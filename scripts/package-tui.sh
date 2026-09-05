#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
manifest_version=$(awk -F '"' '/^version = "/ { print $2; exit }' "$project_dir/Cargo.toml")
version=${1:-$manifest_version}
platform=${2:-}
target=${3:-}
dist_dir="$project_dir/dist"
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/timescale-tui.XXXXXX")

cleanup() {
    rm -rf "$stage_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$dist_dir" "$stage_dir/package"

if [ "$version" != "$manifest_version" ]; then
    echo "Package version $version does not match Cargo version $manifest_version." >&2
    exit 1
fi

if [ "$platform" = "macos-universal" ]; then
    rustup target add aarch64-apple-darwin x86_64-apple-darwin
    cargo build --manifest-path "$project_dir/Cargo.toml" --release --locked \
        --target aarch64-apple-darwin --bin timescale
    cargo build --manifest-path "$project_dir/Cargo.toml" --release --locked \
        --target x86_64-apple-darwin --bin timescale
    lipo -create \
        "$project_dir/target/aarch64-apple-darwin/release/timescale" \
        "$project_dir/target/x86_64-apple-darwin/release/timescale" \
        -output "$stage_dir/package/timescale"
    lipo "$stage_dir/package/timescale" -verify_arch arm64 x86_64
elif [ -n "$target" ]; then
    rustup target add "$target"
    cargo build --manifest-path "$project_dir/Cargo.toml" --release --locked \
        --target "$target" --bin timescale
    cp "$project_dir/target/$target/release/timescale" "$stage_dir/package/timescale"
else
    echo "Usage: $0 VERSION PLATFORM RUST_TARGET" >&2
    exit 2
fi

cp "$project_dir/LICENSE" "$stage_dir/package/LICENSE"
cp "$project_dir/config/example.json" "$stage_dir/package/config.example.json"
chmod +x "$stage_dir/package/timescale"
tar -C "$stage_dir/package" -czf \
    "$dist_dir/Timescale-$version-tui-$platform.tar.gz" .

echo "$dist_dir/Timescale-$version-tui-$platform.tar.gz"
