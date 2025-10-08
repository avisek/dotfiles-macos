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
  ];
}
