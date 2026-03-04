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

  # Shared folder: ~/android-shared on host <-> /sdcard/shared in emulator
  sharedFolderHost = "${homeDir}/android-shared";
  sharedFolderGuest = "/sdcard/shared";
  # Mount here so propagation (shared:N) exposes the FUSE mount through
  # all sdcardfs views (/storage/emulated, /mnt/runtime/{read,write,full}/…),
  # making it visible to apps, not just adb shell.
  sharedFolderGuestMount = "/mnt/runtime/default/emulated/0/shared";

  # Pin the emulator console port so its ADB serial is deterministic,
  # allowing all adb commands to target it even with other devices connected.
  emulatorPort = "5554";
  adbSerial = "emulator-${emulatorPort}";
  adb = "adb -s ${adbSerial}";

  # WebDAV server for shared folder. `adb reverse` tunnels guest :28080 to
  # host :28080 via ADB's direct transport, bypassing the emulator's slow
  # SLiRP user-mode network stack.
  webdavPort = "28080";

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

  # Minimal fusermount3 for Android — rclone's FUSE library expects this
  # binary to open /dev/fuse, call mount(), and pass the fd back via the
  # _FUSE_COMMFD Unix socket. Android has kernel FUSE support but no
  # userspace fusermount, so we cross-compile one with Zig.
  fusermountSrc = pkgs.writeText "fusermount3.c" ''
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <fcntl.h>
    #include <unistd.h>
    #include <sys/mount.h>
    #include <sys/socket.h>

    int main(int argc, char *argv[]) {
        char *mountpoint = NULL;
        char *options = "";
        int unmount = 0;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "-u") == 0) {
                unmount = 1;
            } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
                options = argv[++i];
            } else if (strcmp(argv[i], "--") == 0) {
                if (i + 1 < argc) mountpoint = argv[i + 1];
                break;
            } else if (argv[i][0] != '-') {
                mountpoint = argv[i];
            }
        }

        if (!mountpoint) {
            fprintf(stderr, "fusermount3: missing mountpoint\n");
            return 1;
        }

        if (unmount) return umount2(mountpoint, 0) != 0;

        int fd = open("/dev/fuse", O_RDWR);
        if (fd < 0) { perror("fusermount3: /dev/fuse"); return 1; }

        unsigned long flags = MS_NOSUID | MS_NODEV;
        char fuse_opts[4096];
        fuse_opts[0] = 0;
        char *source = "fuse";
        char fstype[256] = "fuse";

        if (options[0]) {
            char buf[4096];
            strncpy(buf, options, sizeof(buf) - 1);
            buf[sizeof(buf) - 1] = 0;
            char *sv;
            for (char *t = strtok_r(buf, ",", &sv); t; t = strtok_r(NULL, ",", &sv)) {
                if      (strcmp(t, "ro")     == 0) flags |= MS_RDONLY;
                else if (strcmp(t, "nosuid") == 0) flags |= MS_NOSUID;
                else if (strcmp(t, "nodev")  == 0) flags |= MS_NODEV;
                else if (strcmp(t, "noexec") == 0) flags |= MS_NOEXEC;
                else if (strncmp(t, "fsname=", 7) == 0) source = t + 7;
                else if (strncmp(t, "subtype=", 8) == 0)
                    snprintf(fstype, sizeof(fstype), "fuse.%s", t + 8);
                else {
                    if (fuse_opts[0]) strncat(fuse_opts, ",", sizeof(fuse_opts) - strlen(fuse_opts) - 1);
                    strncat(fuse_opts, t, sizeof(fuse_opts) - strlen(fuse_opts) - 1);
                }
            }
        }

        char data[4096];
        snprintf(data, sizeof(data), "fd=%d,rootmode=40000,user_id=0,group_id=0%s%s",
            fd, fuse_opts[0] ? "," : "", fuse_opts);

        if (mount(source, mountpoint, fstype, flags, data) != 0) {
            perror("fusermount3: mount");
            close(fd);
            return 1;
        }

        char *cfd_env = getenv("_FUSE_COMMFD");
        int cfd = cfd_env ? atoi(cfd_env) : 3;
        char zero = 0;
        struct iovec iov = {.iov_base = &zero, .iov_len = 1};
        union { struct cmsghdr h; char b[CMSG_SPACE(sizeof(int))]; } ctrl;
        memset(&ctrl, 0, sizeof(ctrl));
        struct msghdr msg = {
            .msg_iov = &iov, .msg_iovlen = 1,
            .msg_control = ctrl.b, .msg_controllen = sizeof(ctrl.b),
        };
        struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
        cm->cmsg_level = SOL_SOCKET;
        cm->cmsg_type = SCM_RIGHTS;
        cm->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(cm), &fd, sizeof(int));

        if (sendmsg(cfd, &msg, 0) < 0) {
            perror("fusermount3: sendmsg");
            return 1;
        }
        return 0;
    }
  '';

  fusermountAndroid = pkgs.stdenv.mkDerivation {
    name = "fusermount3-aarch64-linux";
    dontUnpack = true;
    nativeBuildInputs = [pkgs.zig];
    buildPhase = ''
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
      zig cc -target aarch64-linux-musl ${fusermountSrc} -o fusermount3
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp fusermount3 $out/bin/
    '';
  };

  # Patch the stock ramdisk with Magisk at Nix build time. Replicates what
  # magiskboot does (CPIO manipulation, fstab patching, backup structure)
  # using standard tools so we don't need the ARM64 Linux magiskboot binary.
  stockRamdisk = "${config.android-sdk.finalPackage}/share/android-sdk/${systemImagePath}ramdisk.img";

  patchedRamdisk = pkgs.stdenv.mkDerivation {
    name = "magisk-patched-ramdisk";
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [cpio gzip xz unzip fakeroot gnused];

    buildPhase = ''
      unzip -oj ${magiskApk} \
        lib/arm64-v8a/libmagiskinit.so \
        lib/arm64-v8a/libmagisk64.so \
        lib/armeabi-v7a/libmagisk32.so \
        -d .

      gunzip -c "${stockRamdisk}" > ramdisk.cpio

      mkdir rootfs
      cd rootfs
      cpio -idm --quiet < ../ramdisk.cpio

      cp init ../init.orig
      cp ../libmagiskinit.so init

      mkdir -p overlay.d/sbin
      xz --check=crc32 -c ../libmagisk32.so > overlay.d/sbin/magisk32.xz
      xz --check=crc32 -c ../libmagisk64.so > overlay.d/sbin/magisk64.xz

      for f in fstab.*; do
        [ -f "$f" ] || continue
        sed -i \
          -e 's/,verify//g' -e 's/verify,//g' \
          -e 's/,avb_keys=[^ ]*//g' \
          -e 's/,avb=[^ ]*//g' -e 's/,avb//g' -e 's/avb,//g' \
          "$f"
      done

      mkdir -p .backup
      cp ../init.orig .backup/init
      printf 'overlay.d\noverlay.d/sbin\noverlay.d/sbin/magisk32.xz\noverlay.d/sbin/magisk64.xz\n' > .backup/.rmlist
      printf 'KEEPVERITY=false\nKEEPFORCEENCRYPT=true\n' > .backup/.magisk

      cd ..

      fakeroot bash -c '
        cd rootfs
        chown -R 0:0 .
        chmod 0750 init
        chmod 0750 overlay.d overlay.d/sbin
        chmod 0644 overlay.d/sbin/magisk32.xz overlay.d/sbin/magisk64.xz
        chmod 000 .backup
        chmod 000 .backup/.magisk
        find . | sort | cpio -o -H newc --quiet | gzip > ../patched.img
      '
    '';

    installPhase = "cp patched.img $out";
  };

  # ── Emulator configuration ─────────────────────────────────────────

  # -qemu must be last: everything after it is passed to QEMU, not the emulator.
  emulatorFlags = lib.concatStringsSep " " [
    "-no-boot-anim"
    "-no-snapstorage"
    "-gpu host"
    "-no-metrics"
    "-no-location-ui"
    "-feature -Vulkan"
    "-port ${emulatorPort}"
  ];
  qemuFlags = "-qemu -append androidboot.serialconsole=0";

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
    hw.audioOutput=yes
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

  # ── Launcher script ────────────────────────────────────────────────

  androidScript = pkgs.writeShellScriptBin "android" ''
    set -euo pipefail

    case "''${1:-}" in
      --delete|-d)
        avdmanager delete avd --name ${avdName}
        echo "AVD '${avdName}' deleted."
        exit 0
        ;;
      "")
        ;;
      *)
        echo "Usage: android [--delete|-d]" >&2
        exit 1
        ;;
    esac

    # ── Create AVD if needed ────────────────────────────────────────
    if [ ! -d "${avdPath}" ]; then
      echo "==> Creating AVD '${avdName}'..."
      echo "no" | avdmanager create avd \
        --name ${avdName} \
        --package "${systemImagePackage}" \
        --tag "${systemImageTag}" \
        --abi "${systemImageAbi}" \
        --force
    fi
    cp -f ${avdConfig} ${avdPath}/config.ini

    # ── Subprocess management ───────────────────────────────────────
    EMU_PID=""
    WEBDAV_PID=""
    cleanup() {
      echo ""
      echo "==> Shutting down..."
      ${adb} shell "su -c 'pkill -f \"rclone mount\" 2>/dev/null'" 2>/dev/null || true
      ${adb} shell "su -c 'umount ${sharedFolderGuestMount} 2>/dev/null'" 2>/dev/null || true
      ${adb} reverse --remove tcp:${webdavPort} 2>/dev/null || true
      [ -n "$WEBDAV_PID" ] && kill "$WEBDAV_PID" 2>/dev/null || true
      [ -n "$EMU_PID" ] && kill "$EMU_PID" 2>/dev/null || true
      wait 2>/dev/null || true
    }
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    # ── Start emulator (subprocess 1) ───────────────────────────────
    echo "==> Starting emulator..."
    emulator -avd ${avdName} ${emulatorFlags} -ramdisk ${patchedRamdisk} ${qemuFlags} &
    EMU_PID=$!

    # ── Wait for boot ───────────────────────────────────────────────
    echo "==> Waiting for boot..."
    ${adb} wait-for-device
    while [ "$(${adb} shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
      sleep 1
    done

    # ── Configure ───────────────────────────────────────────────────
    echo "==> Configuring..."
    ${adb} shell am force-stop com.android.vending
    ${adb} shell cmd appops set com.android.vending RUN_IN_BACKGROUND deny
    ${adb} shell settings put global package_verifier_enable 0
    ${adb} shell settings put global upload_apk_enable 0
    ${adb} shell settings put global verifier_verify_adb_installs 0
    ${adb} shell settings put secure show_ime_with_hard_keyboard 0
    ${adb} shell cmd uimode night yes
    ${adb} shell settings put secure ui_night_mode 2

    if ! ${adb} shell pm list packages 2>/dev/null | grep -q com.topjohnwu.magisk; then
      ${adb} install -r ${magiskApk} 2>/dev/null \
        && echo "  Magisk installed." \
        || echo "  (Magisk install failed)"
      ${adb} shell am start -n com.topjohnwu.magisk/.ui.MainActivity
    fi

    # ── Push shared-folder binaries (skip if present) ───────────────
    if ! ${adb} shell "[ -x /data/local/tmp/rclone ]" 2>/dev/null; then
      echo "==> Pushing rclone to emulator..."
      ${adb} push ${rcloneAndroid}/rclone /data/local/tmp/rclone
      ${adb} shell "su -c 'chmod 755 /data/local/tmp/rclone'"
    fi
    if ! ${adb} shell "[ -x /data/local/tmp/fusermount3 ]" 2>/dev/null; then
      echo "==> Pushing fusermount3 to emulator..."
      ${adb} push ${fusermountAndroid}/bin/fusermount3 /data/local/tmp/fusermount3
      ${adb} shell "su -c 'chmod 755 /data/local/tmp/fusermount3'"
    fi

    # ── Mount shared folder ─────────────────────────────────────────
    echo "==> Mounting shared folder..."
    mkdir -p "${sharedFolderHost}"
    rclone serve webdav "${sharedFolderHost}" \
      --addr 127.0.0.1:${webdavPort} \
      --dir-cache-time 0 \
      --config="" &
    WEBDAV_PID=$!
    sleep 1
    if ! kill -0 "$WEBDAV_PID" 2>/dev/null; then
      echo "Error: WebDAV server failed to start." >&2
      exit 1
    fi

    ${adb} reverse tcp:${webdavPort} tcp:${webdavPort}
    ${adb} shell "su -c 'pkill -f \"rclone mount\" 2>/dev/null; umount ${sharedFolderGuestMount} 2>/dev/null'" || true
    ${adb} shell "su -c 'mkdir -p ${sharedFolderGuestMount}'"
    ${adb} shell "su -c '> /data/local/tmp/rclone-mount.log'"
    ${adb} shell "su -c '
      PATH=/data/local/tmp \
      /data/local/tmp/rclone mount \":webdav:/\" ${sharedFolderGuestMount} \
        --webdav-url http://127.0.0.1:${webdavPort} \
        --vfs-cache-mode writes \
        --cache-dir /data/local/tmp/rclone-cache \
        --dir-cache-time 0 \
        --allow-other \
        --config=\"\" \
        --log-file /data/local/tmp/rclone-mount.log \
        </dev/null >/dev/null 2>&1 &
    '"

    MOUNT_OK=false
    for _ in $(seq 15); do
      if ${adb} shell mount 2>/dev/null | grep -q "${sharedFolderGuestMount}"; then
        MOUNT_OK=true
        break
      fi
      sleep 0.2
    done

    echo ""
    if $MOUNT_OK; then
      echo "Shared folder mounted."
      echo "  Host:  ${sharedFolderHost}"
      echo "  Guest: ${sharedFolderGuest}"
      echo "  Log:   ${adb} shell su -c 'cat /data/local/tmp/rclone-mount.log'"
    else
      echo "Warning: shared folder mount failed." >&2
      echo "  Log:   ${adb} shell su -c 'cat /data/local/tmp/rclone-mount.log'" >&2
    fi
    echo ""

    wait $EMU_PID
  '';
in {
  home.packages = [pkgs.rclone androidScript];

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

  targets.darwin.defaults = {
    "com.android.Emulator" = {
      "set.theme" = 1;
      "set.forwardShortcutsToDevice" = 1;
      "set.crashReportPreference" = 2;
    };
  };
}
