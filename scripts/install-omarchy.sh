#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_dir=${TIMESCALE_INSTALL_DIR:-"${HOME:?}/.local/bin"}
icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"

if ! command -v omarchy-tui-install >/dev/null 2>&1; then
    echo "omarchy-tui-install was not found. Run this script from Omarchy." >&2
    exit 1
fi

if [ "${1:-}" = "--local" ]; then
    cargo build --manifest-path "$project_dir/Cargo.toml" --release --locked --bin timescale
    mkdir -p "$install_dir"
    install -m 755 "$project_dir/target/release/timescale" "$install_dir/timescale"
else
    "$project_dir/scripts/install-tui.sh" "${1:-latest}"
fi
mkdir -p "$icon_dir"
cp "$project_dir/Resources/AppIcon.svg" "$icon_dir/timescale.svg"
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
omarchy-tui-install "Timescale" "$install_dir/timescale" float timescale

echo "Timescale is available from the Omarchy app launcher."
echo "Optional Waybar files are in packaging/waybar/."
