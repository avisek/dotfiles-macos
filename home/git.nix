{
  programs.git = {
    enable = true;

    settings = {
      user.name = "Avisek Das";
      user.email = "avisekdas555@gmail.com";

      init.defaultBranch = "main";
      push.autoSetupRemote = true;

      alias = {
        resetup = "!git fetch && git reset --hard @{u}";
        catchup = "!f() { b=$(git symbolic-ref refs/remotes/origin/HEAD --short | sed 's|origin/||'); git fetch origin \"$b:$b\"; }; f";
      };
    };
  };

  programs.gh.enable = true;
  # echo "n" | gh auth login --git-protocol https --web --skip-ssh-key --clipboard --scopes repo,workflow,project
}
