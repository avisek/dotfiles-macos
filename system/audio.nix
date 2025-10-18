# audio.nix
{pkgs, ...}: {
  homebrew.casks = [
    "blackhole-2ch"
  ];

  nixpkgs.overlays = [
    (final: prev: {
      macos-audio-devices = prev.writeShellScriptBin "macos-audio-devices" ''
        export PATH="${prev.nodejs}/bin:${prev.pnpm}/bin:$PATH"
        exec ${prev.pnpm}/bin/pnpx macos-audio-devices "$@"
      '';
    })
  ];

  environment.systemPackages = with pkgs; [
    macos-audio-devices
    switchaudio-osx
  ];
}
