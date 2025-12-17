{
  lib,
  pkgs,
  config,
  ...
}: let
  blockedUrls = [
    "https://api2.cursor.sh/aiserver.v1.AiService/ReportCommitAiAnalytics"
    "https://api2.cursor.sh/aiserver.v1.AnalyticsService/Batch"
    "https://api2.cursor.sh/aiserver.v1.AiService/ReportClientNumericMetrics"
    "https://api2.cursor.sh/aiserver.v1.AiService/ReportAiCodeChangeMetrics"
    "https://api2.cursor.sh/aiserver.v1.FastApplyService/ReportEditFate"
  ];

  mitmproxyPort = 49200;

  # Get the user's home directory
  homeDir = config.users.users.${config.system.primaryUser}.home;

  # Cursor installation path
  cursorPath =
    "${homeDir}/Applications/Home Manager Apps/Cursor.app"
    + "/Contents/MacOS/Cursor";

  # Convert URL list to mitmproxy blocking rules
  urlsToBlockingRules = urls: let
    parseUrl = url: let
      withoutProtocol =
        lib.removePrefix "https://" (lib.removePrefix "http://" url);
      parts = lib.splitString "/" withoutProtocol;
      host = lib.head parts;
      path = "/" + lib.concatStringsSep "/" (lib.tail parts);
    in {inherit host path;};

    parsed = map parseUrl urls;
    byHost = lib.groupBy (x: x.host) parsed;

    generateHostBlock = host: paths: let
      pathList = lib.concatMapStringsSep ", " (p: ''"${p.path}"'') paths;
    in ''
      "${host}": [${pathList}]'';

    hostBlocks = lib.mapAttrsToList generateHostBlock byHost;
  in
    lib.concatStringsSep ",\n        " hostBlocks;

  blockScript = pkgs.writeText "block-cursor-analytics.py" ''
    from mitmproxy import http
    from datetime import datetime
    import sys

    BLOCKED_ENDPOINTS = {
      ${urlsToBlockingRules blockedUrls}
    }

    def request(flow: http.HTTPFlow) -> None:
      host = flow.request.host
      path = flow.request.path
      method = flow.request.method
      timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]

      # Check if this specific endpoint should be blocked
      is_blocked = (
        host in BLOCKED_ENDPOINTS
        and path in BLOCKED_ENDPOINTS[host]
      )

      if is_blocked:
        status = "🚫 BLOCKED"
      else:
        status = "✓  ALLOWED"

      print(
        f"[{timestamp}] {status} {method:7} {host}{path}",
        file=sys.stderr,
        flush=True
      )

      if is_blocked:
        flow.response = http.Response.make(
          200,
          b"",
          {"Content-Type": "application/proto", "Content-Length": "0"}
        )
  '';

  cursorBlocked = pkgs.writeScriptBin "cursor-blocked" ''
    #!${pkgs.bash}/bin/bash

    CURSOR_PATH="${cursorPath}"

    if [ ! -f "$CURSOR_PATH" ]; then
      echo "Error: Cursor not found at $CURSOR_PATH" >&2
      exit 1
    fi

    export HTTP_PROXY=http://localhost:${toString mitmproxyPort}
    export HTTPS_PROXY=http://localhost:${toString mitmproxyPort}
    exec "$CURSOR_PATH" "$@"
  '';
in {
  environment.systemPackages = with pkgs; [
    mitmproxy
    cursorBlocked
  ];

  # Run mitmproxy as a system daemon
  # Logs: tail -f /tmp/mitmproxy-cursor.log
  launchd.daemons.mitmproxy-cursor = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.mitmproxy}/bin/mitmdump"
        "--mode"
        "regular@${toString mitmproxyPort}"
        "--set"
        "block_global=false"
        "--set"
        "connection_strategy=lazy"
        "--quiet"
        "--scripts"
        "${blockScript}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/mitmproxy-cursor.log";
      StandardErrorPath = "/tmp/mitmproxy-cursor.log";
    };
  };

  # Install mitmproxy CA certificate on system activation
  system.activationScripts.postActivation.text = ''
    CERT_FILE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"

    # Check if certificate is already installed
    if ! security find-certificate -c "mitmproxy" \
        /Library/Keychains/System.keychain &>/dev/null; then
      # Generate certificate if it doesn't exist
      if [ ! -f "$CERT_FILE" ]; then
        echo "Generating mitmproxy certificate..."
        ${pkgs.mitmproxy}/bin/mitmdump \
          --no-server --rfile /dev/null &>/dev/null
      fi

      # Install certificate to system keychain
      if [ -f "$CERT_FILE" ]; then
        echo "Installing mitmproxy CA certificate..."
        if ! security add-trusted-cert -d -r trustRoot \
            -k /Library/Keychains/System.keychain \
            "$CERT_FILE" 2>/dev/null; then
          echo "Error: Failed to install certificate" >&2
        fi
      else
        echo "Error: Certificate file not found at $CERT_FILE" >&2
      fi
    fi
  '';
}
