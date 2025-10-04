{
  programs.git = {
    enable = true;

    userName = "Avisek Das";
    userEmail = "avisekdas555@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;

      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };
}
