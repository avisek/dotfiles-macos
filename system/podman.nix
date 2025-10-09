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
    export DOCKER_HOST="unix://$TMPDIR/podman/podman-machine-default-api.sock"
  '';

  # Podman setup on macOS:
  # podman machine init
  # podman machine start
}
