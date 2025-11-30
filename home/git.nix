{
  programs.gh.enable = true;

  programs.git = {
    enable = true;

    settings = {
      user.name = "Avisek Das";
      user.email = "avisekdas555@gmail.com";

      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };
  };

  # echo "n" | gh auth login --git-protocol https --web --skip-ssh-key --clipboard --scopes repo,workflow
}
