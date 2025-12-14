{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    mitmproxy
  ];
}
