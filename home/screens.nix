{
  config,
  lib,
  ...
}: let
  screensDir = "${config.home.homeDirectory}/android-shared/Screens";
in {
  targets.darwin.defaults = {
    "com.apple.screencapture" = {
      location = screensDir;
      target = "file";
      video = 1;
      style = "selection";
      showsClicks = 1;
    };
  };

  home.activation.createScreensDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${screensDir}"
  '';
}
