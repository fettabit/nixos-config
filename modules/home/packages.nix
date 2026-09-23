{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    vscode
    zotero
    brave
    obsidian
    vesktop
    uv
    nodejs
    libnotify
  ];
}
