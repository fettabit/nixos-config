{...}: {
  # The island shell. QML source of truth is ./quickshell in this repo,
  # copied to the store at build time and materialized read-only at
  # ~/.config/quickshell/island — same edit->rb workflow as the hypr Lua
  # (no hot reload; the rb alias restarts quickshell.service).
  programs.quickshell = {
    enable = true;
    configs.island = ./quickshell;
    activeConfig = "island";
    # quickshell.service: WantedBy graphical-session.target (UWSM-managed),
    # Restart=on-failure (also revives inert `global` binds). systemd owns
    # the single instance — never launch a second by hand: duplicate
    # GlobalShortcut appid:name registrations can crash the shell.
    systemd.enable = true;
  };
}
