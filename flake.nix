{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    mac-app-util.url = "github:hraban/mac-app-util";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nix-darwin,
    home-manager,
    nix-homebrew,
    mac-app-util,
    nix-vscode-extensions,
    ...
  }: {
    darwinConfigurations = {
      "Aviseks-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit self;};
        modules = [
          ./system
          nix-homebrew.darwinModules.default
          mac-app-util.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.sharedModules = [
              mac-app-util.homeManagerModules.default
            ];
          }
          {
            nixpkgs.overlays = [
              nix-vscode-extensions.overlays.default
            ];
          }
          ./home
        ];
      };
    };
  };
}
