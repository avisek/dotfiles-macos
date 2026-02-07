{
  programs.git.includes = [
    {
      condition = "gitdir:~/Work/";
      contents = {
        pull.rebase = false;
      };
    }
    {
      condition = "gitdir:~/Work/symbiofy/";
      contents = {
        user.email = "avisek@symbiofy.ai";
      };
    }
    {
      condition = "gitdir:~/Work/WeframeTech/";
      contents = {
        user.email = "avisek.das@weframetech.com";
      };
    }
  ];
}
