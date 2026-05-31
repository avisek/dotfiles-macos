{pkgs, lib, ...}: let
  nightlight = "${pkgs.nightlight}/bin/nightlight";

  leadMinutes = 5;

  shifts = {
    sleep = {
      temp = 30;
      from = "1am";
      to = "7am";
    };

    nap = {
      temp = 20;
      from = "5pm";
      to = "7pm";
    };
  };

  # Supported forms: "1am", "5pm", "7:30pm" (case-insensitive).
  parseTime = raw: let
    s = lib.toLower raw;
    m = builtins.match "^([0-9]{1,2})(:([0-9]{2}))?(am|pm)$" s;
  in
    if m == null then
      throw "nightshift: invalid time (expected e.g. 1am, 7:30pm): ${raw}"
    else let
      hour12 = builtins.fromJSON (builtins.elemAt m 0);
      minuteStr = builtins.elemAt m 2;
      minute = builtins.fromJSON (if minuteStr == null then "0" else minuteStr);
      meridiem = builtins.elemAt m 3;
      hourBase = lib.mod hour12 12;
      hour = if meridiem == "am" then hourBase else hourBase + 12;
    in {inherit hour minute;};

  timeToMinutes = t: t.hour * 60 + t.minute;

  # Adding a full day before mod keeps the result correct when subtracting
  # leadMinutes crosses midnight (e.g. 1am with 5min lead → 12:55am).
  triggerFor = from: let
    day = 24 * 60;
    normalized = lib.mod (timeToMinutes (parseTime from) - leadMinutes + day) day;
  in {
    hour = normalized / 60;
    minute = lib.mod normalized 60;
  };

  mkAgent = {temp, from, to}: let
    trigger = triggerFor from;
  in {
    serviceConfig.StartCalendarInterval = [{
      Hour = trigger.hour;
      Minute = trigger.minute;
    }];
    script = ''
      ${nightlight} temp ${toString temp}
      ${nightlight} schedule ${from} ${to}
    '';
  };
in {
  launchd.user.agents = lib.mapAttrs' (name: shift: {
    name = "nightshift-${name}";
    value = mkAgent shift;
  }) shifts;

  environment.systemPackages = [pkgs.nightlight];
}
