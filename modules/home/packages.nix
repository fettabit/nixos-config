{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    vscode
    zotero
    firefox
    vesktop
    uv
    nodejs
  ];
}
