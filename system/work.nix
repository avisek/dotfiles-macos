{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    slack
  ];

  # Block Slack auto-update domain
  system.activationScripts.extraActivation.text = ''
    if ! grep -q "downloads.slack-edge.com" /etc/hosts; then
      echo 'Blocking Slack update domain...'
      echo "127.0.0.1 downloads.slack-edge.com" >> /etc/hosts
    fi
  '';

  # Unblock before rebuild so nix can download Slack updates
  environment.interactiveShellInit = ''
    _PRE_NR="
      $_PRE_NR
      echo 'Unblocking Slack update domain...'
      sed -i ''' '/downloads.slack-edge.com/d' /etc/hosts
    "
  '';
}
