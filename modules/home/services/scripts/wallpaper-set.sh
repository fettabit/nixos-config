# Front door for manual wallpaper picks (island QML grid, rofi fallback).
# Queues the pick and activates wallpaper.service — the service script
# (wallpaper-random.sh) consumes the queue and holds the repo's only
# apply block, and the activation resets the 10-min rotation countdown
# (OnUnitActiveSec counts from service activation). Never restart
# wallpaper.timer here: OnActiveSec=5s would fire a random pick 5 s
# later, replacing this one.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"

if [ "$#" -ne 1 ]; then
  echo "usage: wallpaper-set <image-path>" >&2
  exit 1
fi
if [ ! -f "$1" ] || [ ! -r "$1" ]; then
  echo "wallpaper-set: not a readable file: $1" >&2
  exit 1
fi

pick="$(realpath "$1")"
mkdir -p "$STATE_DIR"
printf '%s\n' "$pick" > "$STATE_DIR/wallpaper-next"
systemctl --user start wallpaper.service
