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

  # Block Slack auto-update (re-added on each rebuild)
  # TODO: Migrate to networking.hosts once nix-darwin supports it (like NixOS)
  system.activationScripts.extraActivation.text = ''
    if ! grep -q "downloads.slack-edge.com" /etc/hosts; then
      echo 'Blocking Slack update domain...'
      echo "127.0.0.1 downloads.slack-edge.com" >> /etc/hosts
    fi
  '';

  # Remove host entry
  # sudo sed -i '' '/downloads.slack-edge.com/d' /etc/hosts

  # Hook to unblock Slack domain before nix rebuild (appended to _PRE_NR)
  environment.interactiveShellInit = ''
    _PRE_NR="
      $_PRE_NR
      echo 'Unblocking Slack update domain...'
      sed -i ''' '/downloads.slack-edge.com/d' /etc/hosts
    "
  '';
}
