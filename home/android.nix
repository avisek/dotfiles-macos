# Declarative Android emulator with Magisk root and host-shared folder.
#
# Provides a single `android` command that boots a rooted emulator with
# ~/android-shared mounted at /sdcard/shared via rclone WebDAV + FUSE.
# Magisk is baked into the ramdisk at Nix build time (no runtime patching).
#
# Usage:  android           — launch (creates AVD on first run)
#         android --delete  — remove the AVD (-d shorthand)
{
  config,
  lib,
  pkgs,
  ...
}: let
  # ── AVD parameters ────────────────────────────────────────────────
  avdName = "android-10";
  androidApi = "29";
  systemImageAbi = "arm64-v8a";
  systemImageTag = "google_apis_playstore";

  lcdWidth = 720;
  lcdHeight = 1280;
  lcdDensity = 320;

  # android-nixpkgs uses dashes in package names (e.g. "google-apis-playstore")
  systemImageTagPkg = builtins.replaceStrings ["_"] ["-"] systemImageTag;
  systemImagePackage = "system-images;android-${androidApi};${systemImageTag};${systemImageAbi}";
  systemImagePath = "system-images/android-${androidApi}/${systemImageTag}/${systemImageAbi}/";

  homeDir = config.home.homeDirectory;
  avdPath = "${homeDir}/.android/avd/${avdName}.avd";

  # ── Shared folder paths ───────────────────────────────────────────

  # Shared folder: ~/android-shared on host <-> /sdcard/shared in emulator.
  # Architecture: host runs `rclone serve webdav`, guest mounts it via
  # `rclone mount` (FUSE). `adb reverse` tunnels the connection, bypassing
  # the emulator's slow SLiRP user-mode network stack.
  sharedFolderHost = "${homeDir}/android-shared";
  sharedFolderGuest = "/sdcard/shared"; # for display
  # Must mount under /mnt/runtime/default/ — sdcardfs bind-propagation
  # exposes it through all views (/storage/emulated/0, /mnt/runtime/…),
  # making files visible to apps, not just adb shell.
  sharedFolderGuestMount = "/mnt/runtime/default/emulated/0/shared";

  # ── ADB / network ─────────────────────────────────────────────────

  # Pin the emulator console port so its ADB serial is deterministic,
  # allowing all adb commands to target it even with other devices connected.
  emulatorPort = "5554";
  adbSerial = "emulator-${emulatorPort}";
  adb = "adb -s ${adbSerial}";

  # WebDAV port for shared folder (tunneled via `adb reverse`).
  webdavPort = "28080";

  # ── Pinned dependencies ───────────────────────────────────────────

  # Contains magiskinit (replaces init), magisk32/64 binaries, and the Manager app.
  magiskApk = pkgs.fetchurl {
    url = "https://github.com/topjohnwu/Magisk/releases/download/v25.2/Magisk-v25.2.apk";
    sha256 = "02fm4ss2aac1q8j0h5zg3pm53nh0j84cgcb9lzf059bfif8k5p0b";
  };

  # Static ARM64 Linux binary — runs inside the emulator for FUSE-mounting
  # the host shared folder via WebDAV.
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

  # Patch the stock ramdisk with Magisk at Nix build time using standard
  # tools (cpio/gzip/xz/fakeroot), avoiding the ARM64-only magiskboot binary.
  # Loaded by the emulator via `-ramdisk ${patchedRamdisk}`.
  stockRamdisk = "${config.android-sdk.finalPackage}/share/android-sdk/${systemImagePath}ramdisk.img";

  patchedRamdisk = pkgs.stdenv.mkDerivation {
    name = "magisk-patched-ramdisk";
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [cpio gzip xz unzip fakeroot gnused];

    buildPhase = ''
      # Extract magisk binaries from APK (ELF binaries despite .so extension)
      unzip -oj ${magiskApk} \
        lib/arm64-v8a/libmagiskinit.so \
        lib/arm64-v8a/libmagisk64.so \
        lib/armeabi-v7a/libmagisk32.so \
        -d .

      # Unpack stock ramdisk (gzip-compressed CPIO)
      gunzip -c "${stockRamdisk}" > ramdisk.cpio

      mkdir rootfs
      cd rootfs
      cpio -idm --quiet < ../ramdisk.cpio

      # Replace init with magiskinit (boots magisk before real init)
      cp init ../init.orig
      cp ../libmagiskinit.so init

      # Embed magisk binaries for magiskinit to extract at boot
      mkdir -p overlay.d/sbin
      xz --check=crc32 -c ../libmagisk32.so > overlay.d/sbin/magisk32.xz
      xz --check=crc32 -c ../libmagisk64.so > overlay.d/sbin/magisk64.xz

      # Strip dm-verity and AVB — required for Magisk to modify /system
      for f in fstab.*; do
        [ -f "$f" ] || continue
        sed -i \
          -e 's/,verify//g' -e 's/verify,//g' \
          -e 's/,avb_keys=[^ ]*//g' \
          -e 's/,avb=[^ ]*//g' -e 's/,avb//g' -e 's/avb,//g' \
          "$f"
      done

      # .backup structure: magiskinit needs the original init and a list
      # of files it injected (to hide from SafetyNet / integrity checks)
      mkdir -p .backup
      cp ../init.orig .backup/init
      printf 'overlay.d\noverlay.d/sbin\noverlay.d/sbin/magisk32.xz\noverlay.d/sbin/magisk64.xz\n' > .backup/.rmlist
      printf 'KEEPVERITY=false\nKEEPFORCEENCRYPT=true\n' > .backup/.magisk

      cd ..

      # Repack with root ownership and correct permissions
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

  # Magisk post-fs-data script that unbinds the virtual SD card's virtio device
  # before vold starts, preventing the "Unsupported Virtual SD card" notification.
  # The emulator attaches a virtio-blk device regardless of hw.sdCard=no;
  # unbinding it at the kernel level means vold never sees it.
  disableSdcardScript = pkgs.writeText "disable-sdcard.sh" ''
    #!/system/bin/sh
    dev=$(grep 'voldmanaged=sdcard' /vendor/etc/fstab.ranchu 2>/dev/null | grep -o '/block/vd[a-z]*' | head -1)
    dev=''${dev##*/}
    [ -n "$dev" ] && [ -d "/sys/block/$dev" ] || exit 0
    link=$(readlink "/sys/block/$dev/device" 2>/dev/null)
    virtio=$(echo "$link" | grep -o 'virtio[0-9][0-9]*')
    [ -n "$virtio" ] && echo "$virtio" > /sys/bus/virtio/drivers/virtio_blk/unbind 2>/dev/null
  '';

  # ── Emulator configuration ─────────────────────────────────────────

  # -qemu must be last — everything after it goes to QEMU, not the emulator CLI.
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

  # AVD hardware profile — copied into the AVD directory on each launch so
  # changes here take effect without recreating the AVD.
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
  # Boots the emulator, configures the guest, and mounts the shared folder.
  # Ctrl-C tears down everything (FUSE mount, WebDAV server, emulator).

  androidScript = pkgs.writeShellScriptBin "android" ''
    set -euo pipefail

    # ANSI reset prefix prevents emulator color codes from bleeding into our output
    log() { printf '\033[0m%s\n' "$*"; }

    case "''${1:-}" in
      --delete|-d)
        avdmanager delete avd --name ${avdName}
        log "AVD '${avdName}' deleted."
        exit 0
        ;;
      "")
        ;;
      *)
        log "Usage: android [--delete|-d]" >&2
        exit 1
        ;;
    esac

    # ── Create AVD if needed ────────────────────────────────────────
    if [ ! -d "${avdPath}" ]; then
      log "==> Creating AVD '${avdName}'..."
      echo "no" | avdmanager create avd \
        --name ${avdName} \
        --package "${systemImagePackage}" \
        --tag "${systemImageTag}" \
        --abi "${systemImageAbi}" \
        --force
    fi
    cp -f ${avdConfig} ${avdPath}/config.ini

    # ── Subprocess management ───────────────────────────────────────
    # PIDs tracked in variables (no PID files on disk). EXIT trap cleans up.
    # Teardown order: watcher -> guest mount -> adb tunnel -> host webdav -> emulator
    EMU_PID=""
    WEBDAV_PID=""
    WATCHER_PID=""
    cleanup() {
      log ""
      log "==> Shutting down..."
      [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null || true
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
    # Process substitution > >() keeps $! as the emulator PID (not sed's).
    log "==> Starting emulator..."
    emulator -avd ${avdName} ${emulatorFlags} -ramdisk ${patchedRamdisk} ${qemuFlags} > >(sed 's/^/[emulator] /') 2>&1 &
    EMU_PID=$!

    # ── Wait for boot ───────────────────────────────────────────────
    log "==> Waiting for boot..."
    ${adb} wait-for-device
    while [ "$(${adb} shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
      sleep 1
    done

    # ── Configure (idempotent — settings persist across reboots) ────
    log "==> Configuring..."
    # Disable Play Store auto-updates and Play Protect
    ${adb} shell am force-stop com.android.vending
    ${adb} shell cmd appops set com.android.vending RUN_IN_BACKGROUND deny
    ${adb} shell settings put global package_verifier_enable 0
    ${adb} shell settings put global upload_apk_enable 0
    ${adb} shell settings put global verifier_verify_adb_installs 0
    # Prefer hardware keyboard, enable dark mode
    ${adb} shell settings put secure show_ime_with_hard_keyboard 0
    ${adb} shell cmd uimode night yes
    ${adb} shell settings put secure ui_night_mode 2

    # Install Magisk boot script that suppresses the virtual SD card notification
    if ! ${adb} shell "su -c '[ -f /data/adb/post-fs-data.d/disable-sdcard.sh ]'" 2>/dev/null; then
      ${adb} shell "su -c 'mkdir -p /data/adb/post-fs-data.d'"
      ${adb} push ${disableSdcardScript} /data/local/tmp/disable-sdcard.sh
      ${adb} shell "su -c 'mv /data/local/tmp/disable-sdcard.sh /data/adb/post-fs-data.d/'"
      ${adb} shell "su -c 'chmod 755 /data/adb/post-fs-data.d/disable-sdcard.sh'"
    fi

    # Install Magisk Manager APK (first boot only — ramdisk already has magiskinit)
    if ! ${adb} shell pm list packages 2>/dev/null | grep -q com.topjohnwu.magisk; then
      ${adb} install -r ${magiskApk} 2>/dev/null \
        && log "  Magisk installed." \
        || log "  (Magisk install failed)"
      ${adb} shell am start -n com.topjohnwu.magisk/.ui.MainActivity
    fi

    # ── Push shared-folder binaries (skip if present) ───────────────
    if ! ${adb} shell "[ -x /data/local/tmp/rclone ]" 2>/dev/null; then
      log "==> Pushing rclone to emulator..."
      ${adb} push ${rcloneAndroid}/rclone /data/local/tmp/rclone
      ${adb} shell "su -c 'chmod 755 /data/local/tmp/rclone'"
    fi
    if ! ${adb} shell "[ -x /data/local/tmp/fusermount3 ]" 2>/dev/null; then
      log "==> Pushing fusermount3 to emulator..."
      ${adb} push ${fusermountAndroid}/bin/fusermount3 /data/local/tmp/fusermount3
      ${adb} shell "su -c 'chmod 755 /data/local/tmp/fusermount3'"
    fi

    # ── Mount shared folder ─────────────────────────────────────────
    # Sets up adb reverse tunnel and runs rclone mount inside the guest.
    # Returns 0 if the FUSE mount appears within ~3s, 1 otherwise.
    # Used by both initial mount and the reboot watcher.
    mount_shared() {
      ${adb} reverse tcp:${webdavPort} tcp:${webdavPort}
      ${adb} shell "su -c 'pkill -f \"rclone mount\" 2>/dev/null; umount ${sharedFolderGuestMount} 2>/dev/null'" || true
      ${adb} shell "su -c 'mkdir -p ${sharedFolderGuestMount}'"
      ${adb} shell "su -c '> /data/local/tmp/rclone-mount.log'"
      # PATH lets rclone find fusermount3; </dev/null detaches stdin so the
      # background process survives after the adb shell session ends.
      # --daemon hangs the terminal, so we background manually with &.
      ${adb} shell "su -c '
        PATH=/data/local/tmp \
        /data/local/tmp/rclone mount \":webdav:/\" ${sharedFolderGuestMount} \
          --webdav-url http://127.0.0.1:${webdavPort} \
          --vfs-cache-mode writes \
          --cache-dir /data/local/tmp/rclone-cache \
          --dir-cache-time 3s \
          --allow-other \
          --config=\"\" \
          --log-file /data/local/tmp/rclone-mount.log \
          </dev/null >/dev/null 2>&1 &
      '"
      # Poll until FUSE mount appears (15 × 0.2s = up to 3s)
      for _ in $(seq 15); do
        ${adb} shell mount 2>/dev/null | grep -q "${sharedFolderGuestMount}" && return 0
        sleep 0.2
      done
      return 1
    }

    # Start host-side WebDAV server (subprocess 2) — guest connects via adb reverse
    log "==> Mounting shared folder..."
    mkdir -p "${sharedFolderHost}"
    rclone serve webdav "${sharedFolderHost}" \
      --addr 127.0.0.1:${webdavPort} \
      --dir-cache-time 3s \
      --config="" > >(sed 's/^/[webdav] /') 2>&1 &
    WEBDAV_PID=$!
    sleep 1
    if ! kill -0 "$WEBDAV_PID" 2>/dev/null; then
      log "Error: WebDAV server failed to start." >&2
      exit 1
    fi

    log ""
    if mount_shared; then
      log "Shared folder mounted."
      log "  Host:  ${sharedFolderHost}"
      log "  Guest: ${sharedFolderGuest}"
      log "  Log:   ${adb} shell su -c 'cat /data/local/tmp/rclone-mount.log'"
    else
      log "Warning: shared folder mount failed." >&2
      log "  Log:   ${adb} shell su -c 'cat /data/local/tmp/rclone-mount.log'" >&2
    fi
    log ""

    # ── Reboot watcher (subprocess 3) ─────────────────────────────
    # A guest reboot kills rclone mount and the adb reverse tunnel.
    # This background loop detects mount loss after boot completes and
    # re-establishes both automatically.
    (
      while kill -0 "$EMU_PID" 2>/dev/null; do
        sleep 3
        ${adb} shell mount 2>/dev/null | grep -q "${sharedFolderGuestMount}" && continue
        [ "$(${adb} shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] || continue
        log "==> Re-mounting shared folder (device rebooted)..."
        if mount_shared; then
          log "Shared folder re-mounted."
        else
          log "Warning: shared folder re-mount failed." >&2
        fi
      done
    ) &
    WATCHER_PID=$!

    # Block until the emulator exits (Ctrl-C triggers the EXIT trap)
    wait $EMU_PID
  '';
in {
  home.packages = [pkgs.rclone androidScript];

  # SDK packages managed by android-nixpkgs overlay
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

  # Emulator app preferences (dark theme, forward keyboard shortcuts, no crash reports)
  targets.darwin.defaults = {
    "com.android.Emulator" = {
      "set.theme" = 1;
      "set.forwardShortcutsToDevice" = 1;
      "set.crashReportPreference" = 2;
    };
  };
}
