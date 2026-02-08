{
  homebrew = {
    taps = [
      "dimentium/autoraise"
    ];

    ## TODO: Switch to brew version since cask version cannot autostart.
    ## https://github.com/sbmpost/AutoRaise#readme
    ## https://github.com/Dimentium/homebrew-autoraise
    ## https://github.com/zhaofengli/nix-homebrew
    ## https://claude.ai/chat/91d6a494-45a6-4482-9f30-986fbc35a8e6
    # brews = [
    #   "autoraise"
    # ];
    # services.start = [
    #   "autoraise"
    # ];
    ## I need to discover:
    ## - autoraise cli
    ## - where it puts its config
    ## - how to write config files for all users
    ## - how autostart works

    casks = [
      "dimentium/autoraise/autoraiseapp"
    ];
  };

  system.defaults.CustomUserPreferences = {
    "com.sbmpost.AutoRaise" = {
      autoFocusDelay = 55;
      autoRaiseDelay = 0;
      enableOnLaunch = 1;
    };
  };
}
