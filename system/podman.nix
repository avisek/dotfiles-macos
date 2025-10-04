{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    podman
    podman-compose
  ];

  # virtualisation.podman = lib.mkIf pkgs.stdenv.isLinux {
  #   enable = true;
  #   dockerCompat = true;
  #   defaultNetwork.settings.dns_enabled = true;
  # };

  environment.interactiveShellInit = lib.mkIf pkgs.stdenv.isDarwin ''
    if [ -n "$TMPDIR" ] && [ -S "$TMPDIR/podman/podman-machine-default-api.sock" ]; then
      export DOCKER_HOST="unix://$TMPDIR/podman/podman-machine-default-api.sock"
    fi
  '';

  # Podman setup on macOS:
  # podman machine init
  # podman machine start
}
