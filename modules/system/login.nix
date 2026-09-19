{pkgs, ...}: {
  # Login gate: greetd owns VT1 (the module disables autovt@tty1) and runs
  # tuigreet; on a successful PAM auth it starts the same UWSM session entry
  # bash.nix used to exec on autologin. Restart=on-success (module default)
  # brings the greeter back when Hyprland exits. TTY2+ stay plain gettys —
  # password login, then `sudo nixos-rebuild switch --rollback` if needed.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
  };

  # Secret Service (org.freedesktop.secrets) for Proton's clients and Electron
  # safeStorage. Without it proton-keyring-linux silently falls back to
  # plaintext JSON under ~/.config/Proton. The module wires pam_gnome_keyring
  # into the `login` PAM service; greetd's PAM service is a substack of
  # `login`, so the keyring is created on first login and unlocked with the
  # login password from then on — no extra PAM config.
  services.gnome.gnome-keyring.enable = true;
}
