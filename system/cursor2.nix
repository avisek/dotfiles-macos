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
    import time

    BLOCKED_ENDPOINTS = {
        ${urlsToBlockingRules blockedUrls}
    }

    # ANSI color codes
    GRAY = "\033[90m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    MAGENTA = "\033[95m"
    WHITE = "\033[97m"
    RESET = "\033[0m"

    def request(flow: http.HTTPFlow) -> None:
        flow.metadata["start_time"] = time.time()

        host = flow.request.host
        path = flow.request.path

        is_blocked = host in BLOCKED_ENDPOINTS and path in BLOCKED_ENDPOINTS[host]

        if is_blocked:
            flow.response = http.Response.make(
                200,
                b"",
                {"Content-Type": "application/proto", "Content-Length": "0"}
            )

    def response(flow: http.HTTPFlow) -> None:
        host = flow.request.host
        path = flow.request.path
        method = flow.request.method
        timestamp = datetime.now().strftime("%H:%M:%S")

        is_blocked = host in BLOCKED_ENDPOINTS and path in BLOCKED_ENDPOINTS[host]

        status = flow.response.status_code if flow.response else 0
        size = len(flow.response.content) if flow.response else 0
        content_type = flow.response.headers.get("content-type", "").split(";")[0] if flow.response else ""

        start_time = flow.metadata.get("start_time", time.time())
        response_time = (time.time() - start_time) * 1000

        # Format size
        if size < 1024:
            size_str = f"{size}b"
        elif size < 1024 * 1024:
            size_str = f"{size/1024:.1f}k"
        else:
            size_str = f"{size/(1024*1024):.1f}M"

        # Format time
        time_str = f"{int(response_time)}ms" if response_time < 1000 else f"{response_time/1000:.1f}s"

        # Parse and format path: highlight last segment, dim query params
        if "?" in path:
            path_part, query_part = path.split("?", 1)
            query_str = f"{GRAY}?{query_part}{RESET}"
        else:
            path_part = path
            query_str = ""

        path_segments = path_part.split("/")
        if len(path_segments) > 1 and path_segments[-1]:
            base_path = "/".join(path_segments[:-1])
            last_segment = path_segments[-1]
            formatted_path = f"{GRAY}{base_path}/{RESET}{WHITE}{last_segment}{RESET}{query_str}"
        else:
            formatted_path = f"{WHITE}{path_part}{RESET}{query_str}"

        # Format status with blocked indicator
        if is_blocked:
            status_str = f"🚫 {RED}{status}{RESET}"
        elif status == 200:
            status_str = f"{GREEN}{status}{RESET}"
        elif 400 <= status < 500:
            status_str = f"{YELLOW}{status}{RESET}"
        elif status >= 500:
            status_str = f"{RED}{status}{RESET}"
        else:
            status_str = f"{status}"

        method_color = YELLOW if method == "POST" else BLUE
        content_type_str = f"{CYAN}{content_type}{RESET}" if content_type else f"{GRAY}-{RESET}"

        # Format: TIME METHOD HOST/PATH STATUS TYPE SIZE TIME
        print(
            f"{GRAY}{timestamp}{RESET} "
            f"{method_color}{method:4}{RESET} "
            f"{host}{formatted_path} "
            f"{status_str} "
            f"{content_type_str} "
            f"{MAGENTA}{size_str}{RESET} "
            f"{GRAY}{time_str}{RESET}",
            file=sys.stderr,
            flush=True
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
