{
  programs.gh.enable = true;

  programs.git = {
    enable = true;

    userName = "Avisek Das";
    userEmail = "avisekdas555@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };

    includes = [
      {
        condition = "gitdir:~/Work/symbiofy/";
        contents = {
          user = {
            email = "avisek@symbiofy.ai";
          };
        };
      }
    ];
  };

  # echo "n" | gh auth login --git-protocol https --web --skip-ssh-key --clipboard
}
