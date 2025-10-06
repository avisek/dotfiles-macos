{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    slack
  ];

  system.defaults.CustomUserPreferences = {
    "com.tinyspeck.slackmacgap" = {
      AutoUpdate = false;
    };
  };
}
