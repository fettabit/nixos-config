{ ... }:
{
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
        # Matugen-generated colors; regenerated on wallpaper change and
        # applied live via SIGUSR1 from matugen-reload. Kitty warns but
        # starts fine if the file doesn't exist yet.
        extraConfig = "include /tmp/kitty-matugen-colors.conf";
    };
}