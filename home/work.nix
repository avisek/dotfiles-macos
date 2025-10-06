{
  programs.git.includes = [
    {
      condition = "gitdir:~/Work/symbiofy/";
      contents = {
        user = {
          email = "avisek@symbiofy.ai";
        };
      };
    }
  ];
}
