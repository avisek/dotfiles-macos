{
  system.defaults.CustomUserPreferences = {
    "com.apple.screencapture" = {
      location = "~/Screens";
      target = "file";
      video = 1;
      style = "selection";
      showsClicks = 1;
    };
  };

  system.activationScripts.extraActivation.text = ''
    if [ ! -d /Users/avisek/Screens ]; then
      mkdir -p /Users/avisek/Screens
      chown avisek:staff /Users/avisek/Screens
    fi
  '';
}
