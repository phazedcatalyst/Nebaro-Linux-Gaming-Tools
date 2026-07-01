#!/bin/bash
# Symlinks all widget files into ~/.config/conky/

DEST="$HOME/.config/conky"
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DEST"

for f in gaming.conf gaming.lua draw.lua update_cache.py read_gaming.py wow_tracker.sh wow_hours.json; do
    ln -sf "$SRC/$f" "$DEST/$f"
    echo "linked $f"
done

# Don't symlink steam_cache.json — it's generated in place
if [ ! -f "$DEST/steam_cache.json" ]; then
    cp "$SRC/steam_cache.json" "$DEST/steam_cache.json"
    echo "copied steam_cache.json"
fi

chmod +x "$DEST/wow_tracker.sh"
echo "done — run: conky --config=$DEST/gaming.conf --daemonize"
