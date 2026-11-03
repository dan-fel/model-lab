#!/bin/sh
# Copy this checkout into a project as a development install of the plugin.
#   scripts/install-dev.sh <project folder> [plugin folder id]
# Files are synced into the existing folder, never by replacing the folder:
# Jaide's registration is tied to the folder itself, and a replaced folder
# cannot be reloaded. Development files (tests, docs, skills, scripts) stay
# out, and are removed if an earlier install copied them.
set -eu
project=${1:?usage: install-dev.sh <project folder> [plugin folder id]}
id=${2:-model-lab}
source=$(cd "$(dirname "$0")/.." && pwd)
target="$project/.jaide/plugins/$id"
mkdir -p "$target"
rsync -a --delete --delete-excluded --exclude .git --exclude .DS_Store --exclude node_modules --exclude scripts --exclude tests --exclude skills --exclude docs --exclude AGENTS.md "$source/" "$target/"
if [ "$id" != "model-lab" ]; then
    # A second install under another id needs its own id and runner path.
    sed -i '' -e "s/^id = \"model-lab\"/id = \"$id\"/" -e "s/^name = \"Model Lab\"/name = \"Model Lab ($id)\"/" "$target/plugin.toml"
    sed -i '' -e "s#^local ROOT = '.jaide/plugins/model-lab'#local ROOT = '.jaide/plugins/$id'#" "$target/plugin.luau"
fi
echo "Installed $source into $target"
