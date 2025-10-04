{
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "github.com" = {
        identityFile = "~/.ssh/github";
        identitiesOnly = true;
      };
    };
  };
}
