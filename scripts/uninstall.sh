#!/bin/sh
set -eu

install_dir=${TIMESCALE_INSTALL_DIR:-/Applications}
installed_app="$install_dir/Timescale.app"

running_pid=$(pgrep -f '^/Applications/Timescale.app/Contents/MacOS/Timescale$' || true)
if [ -n "$running_pid" ]; then
    kill "$running_pid"
fi

rm -rf "$installed_app"
echo "Removed $installed_app"
echo "Preferences were preserved. Remove them with: defaults delete com.davafons.timescale"
