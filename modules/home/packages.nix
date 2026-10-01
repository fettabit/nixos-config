{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    vscode
    brave
    obsidian
    vesktop
    uv
    nodejs
    libnotify
  ];
}
