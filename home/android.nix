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

  homeDir = config.home.homeDirectory;
  username = config.home.username;

  # Shared folder: ~/android-shared on host <-> /sdcard/shared in emulator
  sharedFolderHost = "${homeDir}/android-shared";
  sharedFolderGuest = "/sdcard/shared";

  # Mutable working directories (outside Nix store)
  magiskDir = "${homeDir}/.android/magisk";
  patchedRamdiskPath = "${magiskDir}/ramdisk.img";
  sshKeyDir = "${homeDir}/.android/shared";
  sshKeyPath = "${sshKeyDir}/id_ed25519";

  # ── Pinned dependencies ─────────────────────────────────────────────

  magiskApk = pkgs.fetchurl {
    url = "https://github.com/topjohnwu/Magisk/releases/download/v25.2/Magisk-v25.2.apk";
    sha256 = "02fm4ss2aac1q8j0h5zg3pm53nh0j84cgcb9lzf059bfif8k5p0b";
  };

  rcloneAndroid = pkgs.fetchzip {
    url = "https://downloads.rclone.org/v1.69.1/rclone-v1.69.1-linux-arm64.zip";
    sha256 = "0m5y4z5g409100yxwzi199xx7nwisbd4a9kycv09xczc8ala7p94";
    stripRoot = true;
  };

  # ── Device-side scripts (pushed to emulator, run inside Android) ────

  # Patches the stock ramdisk with Magisk. Expects magiskboot, magiskinit,
  # magisk32, magisk64, and ramdisk.cpio.tmp at /data/local/tmp/.
  magiskPatchScript = pkgs.writeText "magisk-patch.sh" ''
    set -e
    cd /data/local/tmp

    chmod 755 magiskboot magiskinit magisk64 magisk32

    ./magiskboot decompress ramdisk.cpio.tmp ramdisk.cpio
    cp ramdisk.cpio ramdisk.cpio.orig

    echo 'KEEPVERITY=false' > config
    echo 'KEEPFORCEENCRYPT=true' >> config

    ./magiskboot compress=xz magisk32 magisk32.xz
    ./magiskboot compress=xz magisk64 magisk64.xz

    ./magiskboot cpio ramdisk.cpio \
      "add 0750 init magiskinit" \
      "mkdir 0750 overlay.d" \
      "mkdir 0750 overlay.d/sbin" \
      "add 0644 overlay.d/sbin/magisk32.xz magisk32.xz" \
      "add 0644 overlay.d/sbin/magisk64.xz magisk64.xz" \
      "patch" \
      "backup ramdisk.cpio.orig" \
      "mkdir 000 .backup" \
      "add 000 .backup/.magisk config"

    rm -f ramdisk.cpio.orig config magisk*.xz magiskinit magisk32 magisk64
    ./magiskboot compress=gzip ramdisk.cpio ramdisk.cpio.gz
    rm -f ramdisk.cpio ramdisk.cpio.tmp magiskboot
  '';

  # Mounts the host shared folder via rclone SFTP + FUSE.
  sharedMountScript = pkgs.writeText "mount-shared.sh" ''
    #!/system/bin/sh
    /data/local/tmp/rclone mount \
      ":sftp:${sharedFolderHost}" ${sharedFolderGuest} \
      --sftp-host 10.0.2.2 \
      --sftp-user ${username} \
      --sftp-key-file /data/local/tmp/id_ed25519 \
      --sftp-known-hosts-file /data/local/tmp/known_hosts \
      --sftp-set-modtime=false \
      --no-modtime \
      --vfs-cache-mode off \
      --daemon
  '';

  # ── Host-side scripts (run on macOS, orchestrate via adb) ───────────

  androidRootScript = pkgs.writeShellScript "android-root" ''
    set -euo pipefail

    RAMDISK_STOCK="$ANDROID_SDK_ROOT/${systemImagePath}ramdisk.img"
    MAGISK_DIR="${magiskDir}"
    RAMDISK_PATCHED="${patchedRamdiskPath}"

    if [ -f "$RAMDISK_PATCHED" ]; then
      echo "Patched ramdisk already exists at: $RAMDISK_PATCHED"
      echo "Delete it first to re-patch: rm \"$RAMDISK_PATCHED\""
      exit 1
    fi

    if [ ! -f "$RAMDISK_STOCK" ]; then
      echo "Stock ramdisk not found at: $RAMDISK_STOCK"
      echo "Make sure ANDROID_SDK_ROOT is set and the system image is installed."
      exit 1
    fi

    echo "==> Waiting for emulator..."
    adb wait-for-device

    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    echo "==> Extracting Magisk v25.2 binaries..."
    unzip -oj ${magiskApk} \
      'lib/arm64-v8a/libmagiskboot.so' \
      'lib/arm64-v8a/libmagiskinit.so' \
      'lib/arm64-v8a/libmagisk64.so' \
      'lib/arm64-v8a/libmagisk32.so' \
      -d "$WORK"

    echo "==> Pushing files to emulator..."
    adb push "$WORK/libmagiskboot.so" /data/local/tmp/magiskboot
    adb push "$WORK/libmagiskinit.so" /data/local/tmp/magiskinit
    adb push "$WORK/libmagisk64.so"   /data/local/tmp/magisk64
    adb push "$WORK/libmagisk32.so"   /data/local/tmp/magisk32
    adb push "$RAMDISK_STOCK"         /data/local/tmp/ramdisk.cpio.tmp
    adb push ${magiskPatchScript}     /data/local/tmp/patch-ramdisk.sh

    echo "==> Patching ramdisk inside emulator..."
    adb shell sh /data/local/tmp/patch-ramdisk.sh

    echo "==> Pulling patched ramdisk..."
    mkdir -p "$MAGISK_DIR"
    adb pull /data/local/tmp/ramdisk.cpio.gz "$RAMDISK_PATCHED"

    echo "==> Cleaning up emulator temp files..."
    adb shell rm -f /data/local/tmp/ramdisk.cpio.gz /data/local/tmp/patch-ramdisk.sh

    echo "==> Installing Magisk Manager app..."
    adb install ${magiskApk} || echo "(Magisk app install skipped — install it manually from the APK)"

    echo ""
    echo "Done! Patched ramdisk saved to: $RAMDISK_PATCHED"
    echo "Close the emulator and restart with: android-start"
    echo "Magisk will be active on the next cold boot."
  '';

  androidSharedSetupScript = pkgs.writeShellScript "android-shared-setup" ''
    set -euo pipefail

    echo "==> Creating shared folder on host..."
    mkdir -p "${sharedFolderHost}"

    echo "==> Waiting for emulator..."
    adb wait-for-device

    echo "==> Pushing rclone binary to emulator..."
    adb push ${rcloneAndroid}/rclone /data/local/tmp/rclone
    adb shell "su -c 'chmod 755 /data/local/tmp/rclone'"

    echo "==> Setting up SSH key pair..."
    mkdir -p "${sshKeyDir}"
    if [ ! -f "${sshKeyPath}" ]; then
      ssh-keygen -t ed25519 -f "${sshKeyPath}" -N "" -C "android-emulator"
      echo "  Generated new SSH key pair."
    else
      echo "  SSH key already exists, reusing."
    fi

    mkdir -p "${homeDir}/.ssh"
    touch "${homeDir}/.ssh/authorized_keys"
    chmod 600 "${homeDir}/.ssh/authorized_keys"
    if ! grep -qF "android-emulator" "${homeDir}/.ssh/authorized_keys"; then
      cat "${sshKeyPath}.pub" >> "${homeDir}/.ssh/authorized_keys"
      echo "  Added public key to ~/.ssh/authorized_keys."
    else
      echo "  Public key already in authorized_keys."
    fi

    echo "==> Pushing SSH private key to emulator..."
    adb push "${sshKeyPath}" /data/local/tmp/id_ed25519
    adb shell "su -c 'chmod 600 /data/local/tmp/id_ed25519'"

    echo "==> Setting up host key verification..."
    HOST_KEY=$(cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
            || cat /etc/ssh/ssh_host_rsa_key.pub 2>/dev/null \
            || echo "")
    if [ -n "$HOST_KEY" ]; then
      KEY_TYPE=$(echo "$HOST_KEY" | awk '{print $1}')
      KEY_DATA=$(echo "$HOST_KEY" | awk '{print $2}')
      echo "10.0.2.2 $KEY_TYPE $KEY_DATA" > "${sshKeyDir}/known_hosts"
      adb push "${sshKeyDir}/known_hosts" /data/local/tmp/known_hosts
      echo "  Pushed host key for 10.0.2.2."
    else
      echo "  Warning: Could not find host SSH public key."
      echo "  Host key verification will not be available."
    fi

    echo "==> Pushing mount script to emulator..."
    adb push ${sharedMountScript} /data/local/tmp/mount-shared.sh
    adb shell "su -c 'chmod 755 /data/local/tmp/mount-shared.sh'"

    echo "==> Creating mount point in emulator..."
    adb shell "su -c 'mkdir -p ${sharedFolderGuest}'"

    echo ""
    echo "Setup complete!"
    echo "  Host folder:    ${sharedFolderHost}"
    echo "  Emulator mount: ${sharedFolderGuest}"
    echo ""
    echo "Use 'android-shared-mount' to mount the shared folder."
    echo ""
    echo "Make sure macOS Remote Login (SSH) is enabled:"
    echo "  System Settings > General > Sharing > Remote Login"
  '';

  androidSharedMountScript = pkgs.writeShellScript "android-shared-mount" ''
    set -euo pipefail
    echo "==> Mounting ${sharedFolderHost} at ${sharedFolderGuest}..."
    adb shell "su -c 'mkdir -p ${sharedFolderGuest}'"
    adb shell "su -c 'sh /data/local/tmp/mount-shared.sh'"
    echo "Mounted. Files are accessible at ${sharedFolderGuest} inside the emulator."
  '';

  androidSharedUmountScript = pkgs.writeShellScript "android-shared-umount" ''
    set -euo pipefail
    echo "==> Unmounting ${sharedFolderGuest}..."
    adb shell "su -c 'umount ${sharedFolderGuest}'" 2>/dev/null \
      || adb shell "su -c 'kill \$(cat /data/local/tmp/rclone.pid)'" 2>/dev/null \
      || echo "Could not unmount (may not be mounted)."
    echo "Done."
  '';

  # ── Emulator configuration ─────────────────────────────────────────

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
    android-start = "cp -f ${avdConfig} ${avdPath}/config.ini && emulator -avd ${avdName} ${emulatorFlags}" + " $([ -f ${patchedRamdiskPath} ] && echo '-ramdisk ${patchedRamdiskPath}')";

    android-root = "${androidRootScript}";
    android-shared-setup = "${androidSharedSetupScript}";
    android-shared-mount = "${androidSharedMountScript}";
    android-shared-umount = "${androidSharedUmountScript}";
  };

  targets.darwin.defaults = {
    "com.android.Emulator" = {
      "set.theme" = 1;
      "set.forwardShortcutsToDevice" = 1;
      "set.crashReportPreference" = 2;
    };
  };
}
