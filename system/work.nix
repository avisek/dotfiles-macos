{
  pkgs,
  lib,
  ...
}:
{
  # Slack is only available on Darwin
  environment.systemPackages = lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
    slack
  ]);
}
# Darwin-specific Slack configuration
// lib.optionalAttrs pkgs.stdenv.isDarwin {
  # Clear Slack data
  # rm -rf /Users/avisek/Library/Application\ Support/Slack
  # rm -rf /Users/avisek/Library/Preferences/com.tinyspeck.slackmacgap.plist
  # rm -rf /Users/avisek/Library/HTTPStorages/com.tinyspeck.slackmacgap
  # rm -rf /Users/avisek/Library/HTTPStorages/com.tinyspeck.slackmacgap.binarycookies
  # rm -rf /Users/avisek/Library/Caches/com.tinyspeck.slackmacgap.ShipIt
  # rm -rf /Users/avisek/Library/Caches/com.tinyspeck.slackmacgap

  # Block Slack auto-update (re-added on each rebuild)
  # TODO: Migrate to networking.hosts once nix-darwin supports it (like NixOS)
  system.activationScripts.extraActivation.text = ''
    if ! grep -q "downloads.slack-edge.com" /etc/hosts; then
      echo "127.0.0.1 downloads.slack-edge.com" >> /etc/hosts
    fi
  '';

  # Hook to unblock Slack domain before nix rebuild
  # Runs before nrs via /etc/nix-hooks/pre-nrs.d/ mechanism in sh.nix
  environment.etc."nix-hooks/pre-nrs.d/slack" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      sudo sed -i "" '/downloads.slack-edge.com/d' /etc/hosts
    '';
  };
}
