{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
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