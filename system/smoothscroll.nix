{
  homebrew.casks = [
    "smoothscroll"
  ];

  system.activationScripts.postActivation.text = ''
    # Configure SmoothScroll preferences for all users
    dscl . list /Users UniqueID | awk '$2 >= 500 && $2 < 65534 {print $1}' | while read -r USER; do
      echo "Configuring SmoothScroll for $USER..."
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll accelerationDelta -int 200
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll accelerationMax -float 999
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll animationTime -int 250
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll bounceAnimation -bool false
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll hasShownReverseWheelDirectionInfo -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll horizontalSmoothing -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll kSSInstallDate -date "9999-01-01 00:00:00 +0000"
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll keyboardSupport -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll launchOnLogin -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll middleButtonSupport -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll pulseAlgorithm -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll pulseScale -float 5
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll reverseWheelDirection -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll showMenuBarIcon -bool true
      sudo -u "$USER" defaults write com.galambalazs.SmoothScroll stepSize -int 40
    done
  '';
}
