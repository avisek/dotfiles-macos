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

  volume-overlay-daemon = pkgs.stdenv.mkDerivation {
    pname = "volume-overlay-daemon";
    version = "1.0.0";

    src = ./audio;

    buildInputs = with pkgs.darwin.apple_sdk.frameworks; [
      AppKit
      Foundation
    ];

    buildPhase = ''
      swiftc -O -o volume-overlay-daemon volume-overlay-daemon.swift \
        -framework AppKit \
        -framework Foundation
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp volume-overlay-daemon $out/bin/
    '';
  };

  volume-overlay-client = pkgs.stdenv.mkDerivation {
    pname = "volume-overlay-client";
    version = "1.0.0";

    src = ./audio;

    buildInputs = with pkgs.darwin.apple_sdk.frameworks; [
      Foundation
    ];

    buildPhase = ''
      swiftc -O -o volume-overlay-client volume-overlay-client.swift \
        -framework Foundation
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp volume-overlay-client $out/bin/
    '';
  };
in {
  homebrew.casks = [
    "blackhole-2ch"
  ];

  environment.systemPackages = with pkgs; [
    macos-audio-devices
    switchaudio-osx
    volume-overlay-daemon
    volume-overlay-client
  ];

  # Volume overlay daemon launchd service
  launchd.daemons.volume-overlay = {
    serviceConfig = {
      Label = "com.volume-overlay.daemon";
      ProgramArguments = ["${volume-overlay-daemon}/bin/volume-overlay-daemon"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/volume-overlay.log";
      StandardErrorPath = "/var/log/volume-overlay.error.log";
    };
  };
}
