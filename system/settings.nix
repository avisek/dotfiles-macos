{config, ...}: let
  homeDir = config.users.users.${config.system.primaryUser}.home;
in {
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };
    finder = {
      _FXShowPosixPathInTitle = true;
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXPreferredViewStyle = "Nlsv";
      FXRemoveOldTrashItems = true;
    };
    dock = {
      autohide = true;
      show-recents = false;
      static-only = true;
      persistent-apps = [
        {app = "/Applications/Nix Apps/Google Chrome.app";}
        {app = "/Applications/Nix Apps/kitty.app";}
        {app = "${homeDir}/Applications/Home Manager Apps/Cursor.app";}
        {app = "/Applications/Nix Apps/Slack.app";}
      ];
      showhidden = true;
      wvous-br-corner = 1;
      appswitcher-all-displays = true;
    };
    CustomUserPreferences.NSGlobalDomain = {
      "com.apple.mouse.linear" = true;
    };
  };
}
