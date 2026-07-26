{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    vscode
    zotero
    brave
    vesktop
    uv
    nodejs
    libnotify
  ];
}
