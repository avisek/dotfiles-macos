{pkgs, ...}: {
  services.skhd = {
    enable = true;
    skhdConfig = ''
      ctrl - f18 : ${pkgs.m1ddc}/bin/m1ddc set input 17
      alt - n : nightlight toggle
    '';
  };

  # Restart skhd service
  # launchctl kickstart -k gui/$(id -u)/org.nixos.skhd
}
