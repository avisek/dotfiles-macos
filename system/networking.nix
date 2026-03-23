{
  system.activationScripts.networking.text = ''
    # Keep USB ethernet adapters below Wi-Fi in network service priority order.
    networksetup -ordernetworkservices \
      "Thunderbolt Bridge" \
      "Wi-Fi" \
      "USB 10/100 LAN"
  '';
}
