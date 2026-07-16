WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"

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

for img in "${images[@]}"; do
  if [ "$(basename "$img")" = "$sel" ]; then
    # apply + rotation-countdown reset via the shared front door
    exec wallpaper-set "$img"
  fi
done
