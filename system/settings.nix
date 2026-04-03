{
  system.defaults = {
    NSGlobalDomain = {
      # Dark mode
      AppleInterfaceStyle = "Dark";
      # Delay before key repeat starts (lower = faster)
      InitialKeyRepeat = 15;
      # Key repeat rate (lower = faster)
      KeyRepeat = 2;
    };

    finder = {
      # Show full path in Finder title bar
      _FXShowPosixPathInTitle = true;
      # Always show file extensions
      AppleShowAllExtensions = true;
      # Show hidden files
      AppleShowAllFiles = true;
      # Default to list view
      FXPreferredViewStyle = "Nlsv";
      # Auto-remove items trashed > 30 days ago
      FXRemoveOldTrashItems = true;
    };

    dock = {
      # Auto-hide the Dock
      autohide = true;
      # Don't show recent apps
      show-recents = false;
      # Only show running apps
      static-only = true;
      # Show hidden apps as translucent
      showhidden = true;
      # Bottom-right hot corner: disabled
      wvous-br-corner = 1;
      # Show app switcher on all displays
      appswitcher-all-displays = true;
    };

    # Prevent quarantine ("downloaded from the internet") flag on files
    LaunchServices.LSQuarantine = false;

    CustomUserPreferences = {
      # Prevent .DS_Store on network and USB volumes
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };

      # Disable mouse acceleration, 1:1 tracking speed
      NSGlobalDomain = {
        "com.apple.mouse.linear" = true;
        "com.apple.mouse.scaling" = 1.0;
      };
    };
  };
}
