{pkgs, ...}: let
  # -focusDelay is only available in builds with EXPERIMENTAL_FOCUS_FIRST.
  autoraise = pkgs.autoraise.override {enableExperimentalFocusFirst = true;};
in {
  # Focus-follows-mouse without raising: -delay 0 disables raise,
  # -focusDelay 1 focuses immediately. Hold control to pause.
  launchd.user.agents.autoraise.serviceConfig = {
    ProgramArguments = [
      "${autoraise}/bin/autoraise"
      "-delay"
      "0"
      "-focusDelay"
      "1"
      "-mouseDelta"
      "0"
      "-pollMillis"
      "50"
      "-disableKey"
      "control"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    ProcessType = "Interactive";
  };
}
