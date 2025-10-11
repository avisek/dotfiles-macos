{
  system.defaults = {
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    NSGlobalDomain.AppleShowAllExtensions = true;
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain.InitialKeyRepeat = 15;
    finder.FXPreferredViewStyle = "Nlsv";
    dock = {
      autohide = true;
      persistent-apps = [
        {
          app = "/Applications/Safari.app";
        }
        {
          spacer = {
            small = false;
          };
        }
        {
          spacer = {
            small = true;
          };
        }
        {
          folder = "/System/Applications/Utilities";
        }
        {
          file = "/Users/avisek/Downloads/test.csv";
        }
      ];
      wvous-br-corner = 1
    };
  };
}
