{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    slack
  ];

  # Clear Slack data
  # rm -rf /Users/avisek/Library/Application\ Support/Slack
  # rm -rf /Users/avisek/Library/Preferences/com.tinyspeck.slackmacgap.plist
  # rm -rf /Users/avisek/Library/HTTPStorages/com.tinyspeck.slackmacgap
  # rm -rf /Users/avisek/Library/HTTPStorages/com.tinyspeck.slackmacgap.binarycookies
  # rm -rf /Users/avisek/Library/Caches/com.tinyspeck.slackmacgap.ShipIt
  # rm -rf /Users/avisek/Library/Caches/com.tinyspeck.slackmacgap

  # Block Slack auto-update
  # TODO: Migrate to networking.hosts once nix-darwin supports it (like NixOS)
  system.activationScripts.extraActivation.text = ''
    if ! grep -q "downloads.slack-edge.com" /etc/hosts; then
      echo "127.0.0.1 downloads.slack-edge.com" >> /etc/hosts
    fi
  '';

  # Unblock Slack domain before nix rebuild so updates can be downloaded
  # Hook called by nrs alias in sh.nix (pattern: _pre_nrs_*)
  environment.interactiveShellInit = ''
    _pre_nrs_slack() {
      sudo sed -i '' '/downloads.slack-edge.com/d' /etc/hosts
    }
  '';
}
