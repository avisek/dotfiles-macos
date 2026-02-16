{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users."avisek" = {
      home.username = "avisek";
      home.homeDirectory = "/Users/avisek";

      imports = [
        # ./ssh.nix
        ./sh.nix
        ./git.nix
        ./vscode
        ./work.nix
        ./android.nix
      ];

      home.stateVersion = "25.05";
      programs.home-manager.enable = true;
    };
  };
}
