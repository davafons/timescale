#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_dir=${TIMESCALE_INSTALL_DIR:-/Applications}
installed_app="$install_dir/Timescale.app"

"$project_dir/scripts/build-app.sh"

running_pid=$(pgrep -f '^/Applications/Timescale.app/Contents/MacOS/Timescale$' || true)
if [ -n "$running_pid" ]; then
    kill "$running_pid"
fi

rm -rf "$installed_app"
ditto "$project_dir/build/Timescale.app" "$installed_app"
open "$installed_app"

echo "Installed Timescale at $installed_app"
