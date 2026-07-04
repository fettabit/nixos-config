{...}: {
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "vscode";
      prompt = "enabled";
      pager = "less";
      aliases = {
        ic = "issue create";
        il = "issue list";
      };
    };
  };
}
