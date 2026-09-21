{...}: {
  # ~/.config/mimeapps.list, HM-owned (#39). Before this it was an unmanaged
  # file whose http/https handlers pointed at firefox.desktop / zen-beta.desktop,
  # neither installed; links only reached Brave by fallback. Trade-off, same as
  # caelestia's shell.json: the file is now a read-only store symlink, so apps
  # can no longer register themselves as handlers -- new ones go here.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = let
      browser = "librewolf.desktop";
    in {
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "text/html" = browser;
      "application/xhtml+xml" = browser;

      # Carried over from the previous unmanaged file.
      "x-scheme-handler/discord" = "vesktop.desktop";
      "text/plain" = "code.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      "x-scheme-handler/proton-inbox" = "proton-mail.desktop";
    };
  };
}
