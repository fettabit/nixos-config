WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-current"

mapfile -t images < <(find -L "$WALLPAPER_DIR" -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
     -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) | sort)

n=${#images[@]}
if [ "$n" -eq 0 ]; then
  echo "no images in $WALLPAPER_DIR" >&2
  exit 1
fi

# start the daemon if it is not already up (safety net; autostart normally handles it)
awww query >/dev/null 2>&1 || { awww-daemon >/dev/null 2>&1 & sleep 0.5; }

# read last-set image to avoid picking it again back-to-back
current=""
[ -f "$STATE" ] && current="$(cat "$STATE")"

pick="$current"
if [ "$n" -gt 1 ]; then
  while [ "$pick" = "$current" ]; do
    pick="${images[RANDOM % n]}"
  done
else
  pick="${images[0]}"
fi

mkdir -p "$(dirname "$STATE")"
printf '%s\n' "$pick" > "$STATE"

awww img "$pick" \
  --transition-type any \
  --transition-fps 60 \
  --transition-duration 1

# Regenerate the desktop palette from the new wallpaper. Matugen is the
# canonical color source; matugen-reload pushes it to running consumers.
# A matugen failure must not break wallpaper rotation.
matugen image "$pick" --mode dark --prefer saturation || echo "matugen failed for $pick" >&2
matugen-reload