{pkgs, ...}: {
  fonts.packages = with pkgs; [
    # kitty's font (programs/kitty.nix). caelestia-shell ships its own
    # fontconfig (Material Symbols, Rubik, CaskaydiaCove NF) — nothing here feeds it.
    nerd-fonts.jetbrains-mono
    (pkgs.stdenvNoCC.mkDerivation {
      name = "anthropic-fonts";
      src = ../../fonts/anthropic;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype $out/share/fonts/opentype
        cp $src/*.ttf $out/share/fonts/truetype/ 2>/dev/null || true
        cp $src/*.otf $out/share/fonts/opentype/ 2>/dev/null || true
      '';
    })
  ];
}
