{pkgs, ...}: {
  environment.systemPackages = [pkgs.nightlight];

  system.activationScripts.postActivation.text = ''
    ${pkgs.nightlight}/bin/nightlight temp 30
    ${pkgs.nightlight}/bin/nightlight schedule 11pm 7am
  '';

  launchd.user.agents = {
    nightshift-on-5pm = {
      serviceConfig = {
        StartCalendarInterval = [{Hour = 17;}];
        ProgramArguments = ["${pkgs.nightlight}/bin/nightlight" "on"];
      };
    };

    nightshift-off-7pm = {
      serviceConfig = {
        StartCalendarInterval = [{Hour = 19;}];
        ProgramArguments = ["${pkgs.nightlight}/bin/nightlight" "off"];
      };
    };
  };
}
