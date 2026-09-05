#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
stamp_file="$project_dir/.build/timescale-dev-stamp"
installed_app=/Applications/Timescale.app

rebuild_and_launch() {
    "$project_dir/scripts/build-app.sh"

    running_pid=$(pgrep -f '^/Applications/Timescale.app/Contents/MacOS/Timescale$' || true)
    if [ -n "$running_pid" ]; then
        kill "$running_pid"
    fi

    ditto "$project_dir/build/Timescale.app" "$installed_app"
    open -n "$installed_app"
    touch "$stamp_file"
}

mkdir -p "$project_dir/.build"
touch "$stamp_file"
rebuild_and_launch

echo "Watching Timescale sources. Press Ctrl-C to stop."
while true; do
    if find "$project_dir/Sources" "$project_dir/Resources" "$project_dir/Tests" "$project_dir/Package.swift" -type f -newer "$stamp_file" -print -quit | grep -q .; then
        rebuild_and_launch
    fi
    sleep 1
done
