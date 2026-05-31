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

  parseInt = s:
    let m = builtins.match "^[0-9]+$" s; in
    if m == null
    then throw "nightshift: expected integer, got: ${s}"
    else lib.foldl' (n: c: n * 10 + (builtins.fromJSON c)) 0 (lib.stringToCharacters s);

  parseTime = raw:
    let
      s = lib.toLower raw;
      m12 = builtins.match "^([0-9]{1,2})(:([0-9]{2}))?(am|pm)$" s;
      m24 = builtins.match "^([0-9]{1,2}):([0-9]{2})$" s;
    in
      if m12 != null then
        let
          h = parseInt (builtins.elemAt m12 0);
          minStr = builtins.elemAt m12 2;
          min = if minStr == null then 0 else parseInt minStr;
          ampm = builtins.elemAt m12 3;
          hour =
            if h == 12 && ampm == "am" then 0
            else if h == 12 && ampm == "pm" then 12
            else if ampm == "pm" then h + 12
            else h;
        in
          if h < 1 || h > 12 then throw "nightshift: invalid 12h hour in: ${raw}"
          else if min < 0 || min > 59 then throw "nightshift: invalid minute in: ${raw}"
          else { inherit hour min; }
      else if m24 != null then
        let
          hour = parseInt (builtins.elemAt m24 0);
          min = parseInt (builtins.elemAt m24 1);
        in
          if hour < 0 || hour > 23 then throw "nightshift: invalid 24h hour in: ${raw}"
          else if min < 0 || min > 59 then throw "nightshift: invalid minute in: ${raw}"
          else { inherit hour min; }
      else
        throw "nightshift: invalid time (expected e.g. 1am, 7:30pm, 01:00, 19:30): ${raw}";

  timeToMinutes = t: t.hour * 60 + t.min;

  minutesToTime = total:
    let
      day = 24 * 60;
      normalized = lib.mod (total + day) day;
      hour = builtins.div normalized 60;
      min = normalized - hour * 60;
    in
      { inherit hour min; };

  triggerFor = from: minutesToTime (timeToMinutes (parseTime from) - leadMinutes);

  mkAgent = name: shift:
    let trigger = triggerFor shift.from;
    in {
      serviceConfig.StartCalendarInterval = [{
        Hour = trigger.hour;
        Minute = trigger.min;
      }];
      script = ''
        ${nightlight} temp ${toString shift.temp}
        ${nightlight} schedule ${shift.from} ${shift.to}
      '';
    };
in {
  launchd.user.agents = lib.mapAttrs' (name: shift: {
    name = "nightshift-${name}";
    value = mkAgent name shift;
  }) shifts;

  environment.systemPackages = [pkgs.nightlight];
}
