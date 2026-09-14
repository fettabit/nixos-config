{...}: {
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 16;
    };
    settings = {
      cursor_shape = "block";
      window_padding_width = 10;
      confirm_os_window_close = 0;
      scrollback_lines = 10000;
      enable_audio_bell = "no";
      tab_bar_style = "powerline";
    };
    # Colours come from caelestia-cli as OSC sequences written straight into
    # every /dev/pts (live windows) and replayed by bash for new ones
    # (programs/bash.nix) — no colour file to include.
  };
}
