{...}: {
  programs.git = {
    enable = true;
    settings = {
      user.name = "fettabit";
      user.email = "143643888+fettabit@users.noreply.github.com";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };
  };
}
