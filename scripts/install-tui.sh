#!/bin/sh
set -eu

repository=${TIMESCALE_REPOSITORY:-davafons/timescale}
version=${1:-latest}
install_dir=${TIMESCALE_INSTALL_DIR:-"${HOME:?}/.local/bin"}

if [ "$version" = "latest" ]; then
    version=$(curl -fsSL "https://api.github.com/repos/$repository/releases/latest" \
        | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$version" ]; then
    echo "Could not determine the latest Timescale version." >&2
    exit 1
fi
version=${version#v}

case "$(uname -s):$(uname -m)" in
    Darwin:*) platform=macos-universal ;;
    Linux:x86_64|Linux:amd64) platform=linux-x86_64 ;;
    Linux:aarch64|Linux:arm64) platform=linux-aarch64 ;;
    *) echo "Unsupported platform: $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac

archive="Timescale-$version-tui-$platform.tar.gz"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/timescale-install.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT INT TERM
curl -fL "https://github.com/$repository/releases/download/v$version/$archive" \
    -o "$temporary_dir/$archive"
tar -xzf "$temporary_dir/$archive" -C "$temporary_dir"
mkdir -p "$install_dir"
install -m 755 "$temporary_dir/timescale" "$install_dir/timescale"
echo "Installed Timescale TUI at $install_dir/timescale"
