{...}: {
  # ~/.config/mimeapps.list, HM-owned (#39). Before this it was an unmanaged
  # file whose http/https handlers pointed at firefox.desktop / zen-beta.desktop,
  # neither installed; links only reached Brave by fallback. Trade-off, same as
  # caelestia's shell.json: the file is now a read-only store symlink, so apps
  # can no longer register themselves as handlers -- new ones go here.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = let
      # Brave is the only browser (#41). It stays a plain package in
      # packages.nix -- nothing about it is declarative except this default.
      browser = "brave-browser.desktop";
    in {
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "text/html" = browser;
      "application/xhtml+xml" = browser;

      # Obsidian ships MimeType=x-scheme-handler/obsidian in its own desktop
      # entry, but this file is a store symlink, so obsidian:// deep links only
      # resolve if the handler is declared here.
      "x-scheme-handler/obsidian" = "obsidian.desktop";

      # Carried over from the previous unmanaged file.
      "x-scheme-handler/discord" = "vesktop.desktop";
      "text/plain" = "code.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      "x-scheme-handler/proton-inbox" = "proton-mail.desktop";
    };
  };
}
