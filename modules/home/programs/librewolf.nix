{...}: {
  # Primary browser (#39). Brave stays in packages.nix as the Chromium fallback.
  #
  # Two declarative surfaces, both owned here:
  #  - `settings` -> ~/.librewolf/librewolf.overrides.cfg, which LibreWolf's own
  #    librewolf.cfg loads last, so a defaultPref here beats LibreWolf's default.
  #    Anything not listed stays LibreWolf stock (strict ETP, GPC, HTTPS-only,
  #    DoH off so resolved's DoT stays in charge, disk cache off, DuckDuckGo).
  #  - `policies` -> distribution/policies.json in the wrapped package. nixpkgs
  #    deep-merges it over LibreWolf's shipped policies.json, so its bundled
  #    uBlock Origin and telemetry/AI lockdowns survive; we only add to it.
  # Profile state (Proton Pass sign-in, new-tab wallpaper, imports) is not ours.
  programs.librewolf = {
    enable = true;

    settings = {
      # Fingerprinting: RFP forces every site into light mode and a UTC clock,
      # which fights caelestia's light/dark theming. Use Firefox's granular
      # fingerprintingProtection instead, with all targets except those two
      # (arkenfox's recommended pairing).
      "privacy.resistFingerprinting" = false;
      "privacy.fingerprintingProtection" = true;
      "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC";

      # LibreWolf wipes cookies/site data on close by default. Keep logins.
      "privacy.sanitize.sanitizeOnShutdown" = false;

      # Force our fonts on pages (generic families still map: sans -> Text,
      # serif -> Display). Sites shipping their own icon fonts may break; that
      # is the accepted trade-off. Both fonts: modules/system/fonts.nix.
      "browser.display.use_document_fonts" = 0;
      "font.default.x-western" = "sans-serif";
      "font.name.sans-serif.x-western" = "Anthropic Sans Text";
      "font.name.serif.x-western" = "Anthropic Sans Display";

      # New-tab background image. LibreWolf disables Mozilla's CDN wallpapers
      # (librewolf.externalWallpapers.enabled); a custom upload still works and
      # lives in the profile.
      "browser.newtabpage.activity-stream.newtabWallpapers.customWallpaper.enabled" = true;

      # AMD hardware video decode on Wayland.
      "media.ffmpeg.vaapi.enabled" = true;
    };

    policies.ExtensionSettings = {
      # Proton Pass (AMO id). uBlock Origin comes from LibreWolf's own policy.
      "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi";
      };
    };
  };
}
