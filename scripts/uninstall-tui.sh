#!/bin/sh
set -eu

install_dir=${TIMESCALE_INSTALL_DIR:-"${HOME:?}/.local/bin"}
binary="$install_dir/timescale"

if [ -f "$binary" ]; then
    rm "$binary"
    echo "Removed $binary (settings were preserved)."
else
    echo "Timescale TUI is not installed at $binary."
fi
