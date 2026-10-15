{
  pkgs,
  lib,
  ...
}: {
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
      # cd ~/Work/WeframeTech/ && echo "n" | gh auth login --git-protocol https --web --skip-ssh-key --clipboard --scopes repo,workflow
      condition = "gitdir:~/Work/WeframeTech/";
      contents = {
        user.email = "avisek.das@weframetech.com";
      };
    }
  ];

  home.file."Work/WeframeTech/.envrc".text = ''
    export GH_CONFIG_DIR="$HOME/Work/WeframeTech/.config/gh"
  '';

  # Parent .envrc shared by all platform-* clones (direnv loads parent dirs).
  # Activates pnpm 9 + tooling via ~/Work/symbiofy/shell.nix on cd into any clone.
  home.file."Work/symbiofy/.envrc".text = ''
    use nix ./shell.nix
  '';

  home.activation.allowDirenvWorkspaces = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.direnv}/bin/direnv allow ~/Work/WeframeTech 2>/dev/null || true
    ${pkgs.direnv}/bin/direnv allow ~/Work/symbiofy 2>/dev/null || true
  '';
}
