# Declarative global npm packages (via pnpm).
# Usage: npm-globals add|update|remove <package>
# Binaries are available immediately on PATH.
# Remember to commit package.yaml and pnpm-lock.yaml.
{
  config,
  pkgs,
  ...
}: let
  npmGlobalsDir = "${config.home.homeDirectory}/.dotfiles/home/npm-globals";
in {
  home.shellAliases = {
    npm-globals = "pnpm --dir ${npmGlobalsDir}";
  };

  home.sessionPath = [
    "${npmGlobalsDir}/node_modules/.bin"
  ];

  home.activation.installGlobalNpmPackages = config.lib.dag.entryAfter ["writeBoundary"] ''
    LOCKFILE="${npmGlobalsDir}/pnpm-lock.yaml"
    SENTINEL="${npmGlobalsDir}/node_modules/.lockfile-hash"

    if [ ! -f "$LOCKFILE" ]; then
      echo "[npm-globals] Error: pnpm-lock.yaml not found at $LOCKFILE" >&2
      exit 1
    fi

    CURRENT_HASH=$(${pkgs.coreutils}/bin/sha256sum "$LOCKFILE" | cut -d' ' -f1)

    if [ -f "$SENTINEL" ] && [ "$(cat "$SENTINEL")" = "$CURRENT_HASH" ]; then
      echo "[npm-globals] Packages are up to date"
    else
      echo "[npm-globals] Installing packages..."
      PATH="${pkgs.nodejs}/bin:${pkgs.pnpm}/bin:$PATH" \
        ${pkgs.pnpm}/bin/pnpm install --frozen-lockfile --dir "${npmGlobalsDir}"
      echo "$CURRENT_HASH" > "$SENTINEL"
      echo "[npm-globals] Done"
    fi
  '';
}
