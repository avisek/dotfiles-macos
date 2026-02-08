{
  system.activationScripts.power.text = ''
    sudo pmset -b displaysleep 30
    sudo pmset -c displaysleep 0
    /usr/bin/defaults -currentHost write com.apple.screensaver idleTime -int 0
  '';
}
