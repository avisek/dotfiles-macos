{
  config,
  lib,
  pkgs,
  ...
}: let
  avdName = "android-10";
  androidApi = "29";
  systemImageAbi = "arm64-v8a";
  systemImageTag = "google_apis_playstore";

  lcdWidth = 720;
  lcdHeight = 1280;
  lcdDensity = 320;

  systemImageTagPkg = builtins.replaceStrings ["_"] ["-"] systemImageTag;
  systemImagePackage = "system-images;android-${androidApi};${systemImageTag};${systemImageAbi}";
  systemImagePath = "system-images/android-${androidApi}/${systemImageTag}/${systemImageAbi}/";
  avdPath = "${config.home.homeDirectory}/.android/avd/${avdName}.avd";

  emulatorFlags = lib.concatStringsSep " " [
    "-no-boot-anim"
    "-no-snapstorage"
    "-gpu host"
    "-no-metrics"
    "-no-location-ui"
    "-qemu -append androidboot.serialconsole=0"
  ];

  avdConfig = pkgs.writeText "${avdName}-config.ini" ''
    PlayStore.enabled=yes
    abi.type=${systemImageAbi}
    avd.id=<build>
    avd.ini.encoding=UTF-8
    avd.name=<build>
    disk.cachePartition=yes
    disk.cachePartition.size=66MB
    disk.dataPartition.path=<temp>
    disk.dataPartition.size=6G
    disk.systemPartition.size=0
    disk.vendorPartition.size=0
    fastboot.forceChosenSnapshotBoot=no
    fastboot.forceColdBoot=yes
    fastboot.forceFastBoot=no
    firstboot.bootFromDownloadableSnapshot=no
    firstboot.bootFromLocalSnapshot=no
    firstboot.saveToLocalSnapshot=no
    hw.accelerometer=no
    hw.accelerometer_uncalibrated=no
    hw.arc=no
    hw.arc.autologin=no
    hw.audioInput=no
    hw.audioOutput=no
    hw.battery=no
    hw.camera.back=none
    hw.camera.front=none
    hw.cpu.arch=arm64
    hw.cpu.ncore=4
    hw.dPad=no
    hw.gltransport=pipe
    hw.gltransport.asg.dataRingSize=32768
    hw.gltransport.asg.writeBufferSize=1048576
    hw.gltransport.asg.writeStepSize=4096
    hw.gltransport.drawFlushInterval=800
    hw.gps=no
    hw.gpu.enabled=yes
    hw.gpu.mode=host
    hw.gsmModem=no
    hw.gyroscope=no
    hw.hotplug_multi_display=no
    hw.initialOrientation=portrait
    hw.keyboard=yes
    hw.keyboard.charmap=qwerty2
    hw.keyboard.lid=no
    hw.lcd.backlight=no
    hw.lcd.circular=false
    hw.lcd.density=${toString lcdDensity}
    hw.lcd.depth=16
    hw.lcd.height=${toString lcdHeight}
    hw.lcd.transparent=false
    hw.lcd.vsync=60
    hw.lcd.width=${toString lcdWidth}
    hw.mainKeys=no
    hw.multi_display_window=no
    hw.ramSize=3072
    hw.rotaryInput=no
    hw.screen=multi-touch
    hw.sdCard=no
    hw.sensor.hinge=no
    hw.sensor.hinge.count=0
    hw.sensor.roll=no
    hw.sensor.roll.count=0
    hw.sensors.gyroscope_uncalibrated=no
    hw.sensors.heading=no
    hw.sensors.heart_rate=no
    hw.sensors.humidity=no
    hw.sensors.light=no
    hw.sensors.magnetic_field=no
    hw.sensors.magnetic_field_uncalibrated=no
    hw.sensors.orientation=no
    hw.sensors.pressure=no
    hw.sensors.proximity=no
    hw.sensors.rgbclight=no
    hw.sensors.temperature=no
    hw.sensors.wrist_tilt=no
    hw.touchpad0=no
    hw.trackBall=no
    hw.useext4=yes
    image.sysdir.1=${systemImagePath}
    kernel.newDeviceNaming=autodetect
    kernel.supportsYaffs2=autodetect
    runtime.network.latency=none
    runtime.network.speed=full
    sdcard.size=0
    showDeviceFrame=no
    tag.display=Google Play
    tag.displaynames=Google Play
    tag.id=${systemImageTag}
    tag.ids=${systemImageTag}
    target=android-${androidApi}
    test.delayAdbTillBootComplete=0
    test.monitorAdb=0
    test.quitAfterBootTimeOut=-1
    userdata.useQcow2=no
    vm.heapSize=512M
  '';
in {
  android-sdk = {
    enable = true;

    packages = sdkPkgs: [
      sdkPkgs.cmdline-tools-latest
      sdkPkgs.platform-tools
      sdkPkgs.emulator
      sdkPkgs."platforms-android-${androidApi}"
      sdkPkgs."system-images-android-${androidApi}-${systemImageTagPkg}-${systemImageAbi}"
    ];
  };

  home.shellAliases = {
    android-delete = "avdmanager delete avd --name ${avdName}";
    android-create = ''echo "no" | avdmanager create avd --name ${avdName} --package "${systemImagePackage}" --tag "${systemImageTag}" --abi "${systemImageAbi}" --force'';
    android-start = "cp -f ${avdConfig} ${avdPath}/config.ini && emulator -avd ${avdName} ${emulatorFlags}";
  };

  targets.darwin.defaults = {
    "com.android.Emulator" = {
      "set.theme" = 1;
      "set.forwardShortcutsToDevice" = 1;
      "set.crashReportPreference" = 2;
    };
  };
}
