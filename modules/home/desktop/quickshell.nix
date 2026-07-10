{config, ...}: {
  # The island shell. QML source of truth is ./quickshell in this repo.
  #
  # DEV PHASE: the config is an out-of-store symlink into the repo checkout
  # so QML edits hot-reload live without a rebuild. Step 12 of the plan
  # switches the source to the pure store path (./quickshell) once the
  # core tier is done, matching the hypr-Lua edit->rb workflow.
  programs.quickshell = {
    enable = true;
    configs.island =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixos/modules/home/desktop/quickshell";
    activeConfig = "island";
    # Flipped on in step 12 (autostart swap). Until then the shell is
    # launched manually: `qs -c island`.
    systemd.enable = false;
  };
}
