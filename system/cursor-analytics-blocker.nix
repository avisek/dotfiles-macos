{
  lib,
  pkgs,
  config,
  ...
}: let
  blockedUrls = [
    "api2.cursor.sh/aiserver.v1.AiService/ReportCommitAiAnalytics"
    "api2.cursor.sh/aiserver.v1.AnalyticsService/Batch"
    "api2.cursor.sh/aiserver.v1.AiService/ReportClientNumericMetrics"
    "api2.cursor.sh/aiserver.v1.AiService/ReportAiCodeChangeMetrics"
    "api2.cursor.sh/aiserver.v1.FastApplyService/ReportEditFate"
  ];

  mitmproxyPort = 49200;

  # Get the user's home directory
  homeDir = config.users.users.${config.system.primaryUser}.home;

  # Cursor installation path
  cursorPath = "${homeDir}/Applications/Home Manager Apps/Cursor.app/Contents/MacOS/Cursor";

  # Convert URL list to mitmproxy blocking rules
  urlsToBlockingRules = urls: let
    parseUrl = url: let
      parts = lib.splitString "/" url;
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

        is_blocked = host in BLOCKED_ENDPOINTS and path in BLOCKED_ENDPOINTS[host]
        status = "🚫 BLOCKED" if is_blocked else "✓  ALLOWED"

        print(f"[{timestamp}] {status} {method:7} {host}{path}", file=sys.stderr, flush=True)

        if is_blocked:
            flow.response = http.Response.make(
                200,
                b"",
                {"Content-Type": "application/proto", "Content-Length": "0"}
            )
  '';

  cursorBlocked = pkgs.writeScriptBin "cursor-blocked" ''
    #!${pkgs.bash}/bin/bash
    set -e

    CURSOR_PATH="${cursorPath}"
    CERT_FILE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    MITM_PID=""

    cleanup() {
      if [ -n "$MITM_PID" ] && kill -0 "$MITM_PID" 2>/dev/null; then
        echo "Stopping mitmproxy..."
        kill "$MITM_PID" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT INT TERM

    # Check if Cursor exists
    if [ ! -f "$CURSOR_PATH" ]; then
      echo "Error: Cursor not found at $CURSOR_PATH" >&2
      exit 1
    fi

    # Install certificate if needed
    if ! security find-certificate -c "mitmproxy" /Library/Keychains/System.keychain &>/dev/null; then
      echo "Setting up mitmproxy certificate..."

      # Generate certificate if it doesn't exist
      if [ ! -f "$CERT_FILE" ]; then
        echo "Generating certificate..."
        ${pkgs.mitmproxy}/bin/mitmdump --no-server --rfile /dev/null &>/dev/null
      fi

      # Install certificate to system keychain
      if [ -f "$CERT_FILE" ]; then
        echo "Installing certificate to system keychain (requires password)..."
        if sudo security add-trusted-cert -d -r trustRoot \
            -k /Library/Keychains/System.keychain \
            "$CERT_FILE" 2>/dev/null; then
          echo "Certificate installed successfully!"
        else
          echo "Error: Failed to install certificate" >&2
          exit 1
        fi
      else
        echo "Error: Certificate file not found" >&2
        exit 1
      fi
    fi

    # Start mitmproxy in background
    echo "Starting mitmproxy on port ${toString mitmproxyPort}..."
    ${pkgs.mitmproxy}/bin/mitmdump \
      --mode "regular@${toString mitmproxyPort}" \
      --set block_global=false \
      --set connection_strategy=lazy \
      --quiet \
      -s "${blockScript}" \
      2>&1 &

    MITM_PID=$!

    # Wait for mitmproxy to start
    sleep 1

    # Check if mitmproxy is running
    if ! kill -0 "$MITM_PID" 2>/dev/null; then
      echo "Error: Failed to start mitmproxy" >&2
      exit 1
    fi

    echo "Launching Cursor with analytics blocking..."
    echo "Logs will appear below. Press Ctrl+C to stop."
    echo "---"

    # Launch Cursor with proxy settings
    HTTP_PROXY=http://localhost:${toString mitmproxyPort} \
    HTTPS_PROXY=http://localhost:${toString mitmproxyPort} \
    "$CURSOR_PATH" "$@" &

    CURSOR_PID=$!

    # Wait for Cursor to exit
    wait "$CURSOR_PID" 2>/dev/null || true
  '';
in {
  environment.systemPackages = [
    pkgs.mitmproxy
    cursorBlocked
  ];
}
