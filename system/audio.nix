# audio.nix
{
  pkgs,
  config,
  ...
}: let
  # macos-audio-devices package for managing audio devices
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

  # Volume overlay daemon - Swift app for displaying volume overlay
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

  # Volume overlay client - CLI tool for sending messages to daemon
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

  username = config.users.users.avisek.name;
  userHome = config.users.users.avisek.home;
in {
  homebrew.casks = [
    "blackhole-2ch"
  ];

  environment.systemPackages = [
    macos-audio-devices
    pkgs.switchaudio-osx
    volume-overlay-daemon
    volume-overlay-client
  ];

  # Launchd service for volume overlay daemon
  launchd.user.agents.volume-overlay-daemon = {
    serviceConfig = {
      Label = "com.user.volume-overlay-daemon";
      ProgramArguments = ["${volume-overlay-daemon}/bin/volume-overlay-daemon"];
      EnvironmentVariables = {
        VOLUME_OVERLAY_SOCKET = "${userHome}/.cache/volume-overlay.sock";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${userHome}/.cache/volume-overlay-daemon.log";
      StandardErrorPath = "${userHome}/.cache/volume-overlay-daemon.log";
    };
  };
}
