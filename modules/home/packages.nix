{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    vscode
    obsidian
    vesktop
    uv
    nodejs
    libnotify
  ];
}
