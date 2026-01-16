{
  system.activationScripts.applications.text = ''
    if ! xcode-select -p &> /dev/null; then
      echo "Xcode Command Line Tools not found. Installing..."
      xcode-select --install

      echo "Waiting for Xcode Command Line Tools installation..."
      until xcode-select -p &> /dev/null; do
        sleep 5
      done

      echo "Xcode Command Line Tools installed successfully"
    else
      echo "Xcode Command Line Tools already installed at: $(xcode-select -p)"
    fi
  '';

  homebrew = {
    enable = true;

    casks = [
      # "linearmouse"

      "openmtp"
      # ~/Library/Application\ Support/OpenMTP
      # ~/Library/Application\ Support/io.ganeshrvel.openmtp
      # ~/Library/Preferences/io.ganeshrvel.openmtp.plist

      "iina"
      # "the-unarchiver"
      # "obsidian"
      # "logseq"
      # "notion"
      # "discord"

      "audiorelay"
      "steam"
      "monitorcontrol"
    ];

    # masApps = {
    #   Yoink = 457622435;
    # };

    caskArgs.no_quarantine = true;
    onActivation.cleanup = "zap";
  };

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "avisek";
  };
}
