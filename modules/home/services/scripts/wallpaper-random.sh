WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE="$STATE_DIR/wallpaper-current"
QUEUE="$STATE_DIR/wallpaper-next"

# A queued manual pick (wallpaper-set front door) beats random. The
# queue file is consumed unconditionally — a stale/vanished path must
# not wedge the next rotation — falling through to random if the image
# no longer exists. Runs before the empty-dir guard so a valid queued
# pick applies even when WALLPAPER_DIR is empty.
pick=""
if [ -f "$QUEUE" ]; then
  queued="$(cat "$QUEUE")"
  rm -f "$QUEUE"
  [ -f "$queued" ] && pick="$queued"
fi

if [ -z "$pick" ]; then
  mapfile -t images < <(find -L "$WALLPAPER_DIR" -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) | sort)

  n=${#images[@]}
  if [ "$n" -eq 0 ]; then
    echo "no images in $WALLPAPER_DIR" >&2
    exit 1
  fi

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
fi

# ---- apply: the repo's ONLY wallpaper apply path (manual + random) ----

# start the daemon if it is not already up (safety net; autostart normally handles it)
awww query >/dev/null 2>&1 || { awww-daemon >/dev/null 2>&1 & sleep 0.5; }

mkdir -p "$STATE_DIR"
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
