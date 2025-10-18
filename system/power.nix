{
  system.activationScripts.power.text = ''
    sudo pmset -b displaysleep 30
    sudo pmset -c displaysleep 60
    /usr/bin/defaults -currentHost write com.apple.screensaver idleTime -int 0
  '';
}
