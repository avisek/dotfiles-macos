# audio.nix
{pkgs, ...}: let
  macos-audio-devices = pkgs.stdenv.mkDerivation rec {
    pname = "macos-audio-devices";
    version = "1.4.0";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
      hash = "sha256-U46Oga8c5XgjjdeDSFcr6vVr35e3DCj+qhJQer8yHuQ=";
    };

    installPhase = ''
      mkdir -p $out/bin
      cp audio-devices $out/bin/
      chmod +x $out/bin/audio-devices
    '';
  };
in {
  homebrew.casks = [
    "blackhole-2ch"
  ];

  environment.systemPackages = with pkgs; [
    macos-audio-devices
    switchaudio-osx
  ];
}
