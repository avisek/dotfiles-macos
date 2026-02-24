{lib, ...}: {
  # Enable macOS Remote Login (SSH/SFTP server) for the Android emulator's
  # rclone SFTP shared folder mount. The emulator accesses the host at
  # 10.0.2.2 over SFTP to mount ~/android-shared at /sdcard/shared.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    if ! systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
      echo "Enabling Remote Login (SSH/SFTP) for Android emulator shared folders..."
      systemsetup -setremotelogin on 2>/dev/null || true
    fi
  '';
}
