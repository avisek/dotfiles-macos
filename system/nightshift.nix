{pkgs, ...}: let
  nightlight = "${pkgs.nightlight}/bin/nightlight";
in {
  system.activationScripts.postActivation.text = ''
    ${nightlight} temp 30
  '';

  launchd.user.agents = {
    nightshift-sleep = {
      serviceConfig = {
        StartCalendarInterval = [{Hour = 1 - 1;}];
        ProgramArguments = [nightlight "schedule" "1am" "7am"];
      };
    };

    nightshift-nap = {
      serviceConfig = {
        StartCalendarInterval = [{Hour = 17 - 1;}];
        ProgramArguments = [nightlight "schedule" "5pm" "7pm"];
      };
    };
  };

  environment.systemPackages = [pkgs.nightlight];
}
