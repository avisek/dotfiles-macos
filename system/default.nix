{
  self,
  pkgs,
  ...
}: {
  imports = [
    # ./ssh.nix
    ./sh.nix
    # ./settings.nix
    ./power.nix
    ./audio.nix
    ./screens.nix
    ./nightshift.nix
    ./hotkeys.nix
    ./homebrew.nix
    ./podman.nix
    ./work.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    git
    vim
    tree

    google-chrome

    nixd
    nil
    alejandra

    nodejs
    pnpm
    claude-code

    obsidian
    # mas
    # iina
    # the-unarchiver
  ];

  environment.variables = {
    NEXT_TELEMETRY_DISABLED = "1";
  };

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Enable alternative shell support in nix-darwin.
  # programs.fish.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Declare the user that will be running `nix-darwin`.
  users.users."avisek" = {
    name = "avisek";
    home = "/Users/avisek";
  };

  system.primaryUser = "avisek";
}
