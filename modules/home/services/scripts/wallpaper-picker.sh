WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-current"

mapfile -t images < <(find -L "$WALLPAPER_DIR" -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
     -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) | sort)

if [ "${#images[@]}" -eq 0 ]; then
  echo "no images in $WALLPAPER_DIR" >&2
  exit 1
fi

# rofi extended dmenu rows: "<label>\0icon\x1f<path>" gives a thumbnail per entry
sel="$(
  for img in "${images[@]}"; do
    printf '%s\0icon\x1f%s\n' "$(basename "$img")" "$img"
  done | rofi -dmenu -i -p wallpaper -show-icons
)" || true

[ -z "$sel" ] && exit 0

awww query >/dev/null 2>&1 || { awww-daemon >/dev/null 2>&1 & sleep 0.5; }

for img in "${images[@]}"; do
  if [ "$(basename "$img")" = "$sel" ]; then
    # keep the random-rotation no-repeat logic aware of manual picks
    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$img" > "$STATE"

    awww img "$img" \
      --transition-type any \
      --transition-fps 60 \
      --transition-duration 1

    matugen image "$img" --mode dark --prefer saturation || echo "matugen failed for $img" >&2
    matugen-reload
    exit 0
  fi
done