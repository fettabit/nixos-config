{...}: {
  # Place the hand-written Lua config verbatim at ~/.config/hypr.
  # recursive = true keeps ~/.config/hypr a real writable dir and symlinks each
  # file individually (so the modules/ subtree and require(...) still resolve),
  # instead of making the whole dir one read-only symlink.
  xdg.configFile."hypr" = {
    source = ./hypr;
    recursive = true;
  };
}
