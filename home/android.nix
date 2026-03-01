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

  lcdWidth = 2560;
  lcdHeight = 1440;
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
  # Mount here so propagation (shared:N) exposes the FUSE mount through
  # all sdcardfs views (/storage/emulated, /mnt/runtime/{read,write,full}/…),
  # making it visible to apps, not just adb shell.
  sharedFolderGuestMount = "/mnt/runtime/default/emulated/0/shared";

  # Mutable working directories (outside Nix store)
  magiskDir = "${homeDir}/.android/magisk";
  patchedRamdiskPath = "${magiskDir}/ramdisk.img";

  # WebDAV server for shared folder. `adb reverse` tunnels guest :28080 to
  # host :28080 via ADB's direct transport, bypassing the emulator's slow
  # SLiRP user-mode network stack.
  webdavPort = "28080";
  webdavPidFile = "${magiskDir}/webdav.pid";

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

  # Mounts the host shared folder via rclone WebDAV + FUSE.
  # The host runs `rclone serve webdav` on loopback; the emulator reaches
  # it through `adb reverse` (ADB's direct transport channel), bypassing
  # the emulator's slow SLiRP user-mode network stack (~6x faster).
  sharedMountScript = pkgs.writeText "mount-shared.sh" ''
    #!/system/bin/sh
    export PATH=/data/local/tmp:$PATH
    MOUNT=${sharedFolderGuestMount}

    # Kill any leftover rclone mount from a previous session
    pkill -f "rclone mount" 2>/dev/null || true
    umount "$MOUNT" 2>/dev/null || true
    sleep 0.5
    mkdir -p "$MOUNT"

    /data/local/tmp/rclone mount \
      ":webdav:/" "$MOUNT" \
      --webdav-url http://127.0.0.1:${webdavPort} \
      --vfs-cache-mode writes \
      --cache-dir /data/local/tmp/rclone-cache \
      --no-modtime \
      --allow-other \
      --allow-non-empty \
      --dir-cache-time 0 \
      </dev/null >/dev/null 2>&1 &

    i=0
    while [ $i -lt 50 ]; do
      mount | grep -q "$MOUNT" && exit 0
      sleep 0.2
      i=$((i + 1))
    done
    echo "Error: FUSE mount did not establish" >&2
    exit 1
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
      'lib/armeabi-v7a/libmagisk32.so' \
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

    echo "==> Pushing fusermount3 to emulator..."
    adb push ${fusermountAndroid}/bin/fusermount3 /data/local/tmp/fusermount3
    adb shell "su -c 'chmod 755 /data/local/tmp/fusermount3'"

    echo "==> Pushing mount script to emulator..."
    adb push ${sharedMountScript} /data/local/tmp/mount-shared.sh
    adb shell "su -c 'chmod 755 /data/local/tmp/mount-shared.sh'"

    echo "==> Creating mount point in emulator..."
    adb shell "su -c 'mkdir -p ${sharedFolderGuestMount}'"

    echo ""
    echo "Setup complete!"
    echo "  Host folder:    ${sharedFolderHost}"
    echo "  Emulator mount: ${sharedFolderGuest}"
    echo ""
    echo "Use 'android-shared-mount' to mount the shared folder."
  '';

  androidSharedMountScript = pkgs.writeShellScript "android-shared-mount" ''
    set -euo pipefail

    PID_FILE="${webdavPidFile}"

    # Kill stale server if PID file exists but process is dead or not rclone
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        if ps -p "$OLD_PID" -o command= 2>/dev/null | grep -q "rclone serve"; then
          echo "WebDAV server already running (pid $OLD_PID)."
        else
          echo "Stale PID $OLD_PID (not rclone). Cleaning up."
          rm -f "$PID_FILE"
        fi
      else
        rm -f "$PID_FILE"
      fi
    fi

    if [ ! -f "$PID_FILE" ]; then
      echo "==> Starting WebDAV server on host (127.0.0.1:${webdavPort})..."
      mkdir -p "${sharedFolderHost}"
      rclone serve webdav "${sharedFolderHost}" \
        --addr 127.0.0.1:${webdavPort} \
        --read-only=false \
        --dir-cache-time 0 &
      echo $! > "$PID_FILE"
      sleep 1
      if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Error: WebDAV server failed to start."
        rm -f "$PID_FILE"
        exit 1
      fi
      echo "  WebDAV server started (pid $(cat "$PID_FILE"))."
    fi

    echo "==> Setting up ADB reverse tunnel (guest :${webdavPort} -> host :${webdavPort})..."
    adb reverse tcp:${webdavPort} tcp:${webdavPort}

    echo "==> Mounting inside emulator at ${sharedFolderGuest}..."
    adb shell "su -c 'sh /data/local/tmp/mount-shared.sh'"
    echo "Mounted. Files are accessible at ${sharedFolderGuest} inside the emulator."
  '';

  androidSharedUmountScript = pkgs.writeShellScript "android-shared-umount" ''
    set -euo pipefail

    echo "==> Unmounting ${sharedFolderGuest} in emulator..."
    adb shell "su -c 'pkill -f \"rclone mount\" 2>/dev/null; umount ${sharedFolderGuestMount} 2>/dev/null'" \
      || echo "  (was not mounted)"

    echo "==> Removing ADB reverse tunnel..."
    adb reverse --remove tcp:${webdavPort} 2>/dev/null || true

    PID_FILE="${webdavPidFile}"
    if [ -f "$PID_FILE" ]; then
      echo "==> Stopping WebDAV server on host..."
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi
    echo "Done."
  '';

  # ── Emulator configuration ─────────────────────────────────────────

  # -qemu must be last: everything after it is passed to QEMU, not the emulator.
  emulatorFlags = lib.concatStringsSep " " [
    "-no-boot-anim"
    "-no-snapstorage"
    "-gpu host"
    "-no-metrics"
    "-no-location-ui"
    "-feature -Vulkan"
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
in {
  home.packages = [pkgs.rclone];

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
    android-start = "cp -f ${avdConfig} ${avdPath}/config.ini && emulator -avd ${avdName} ${emulatorFlags}" + " $([ -f ${patchedRamdiskPath} ] && echo '-ramdisk ${patchedRamdiskPath}') ${qemuFlags}";

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
