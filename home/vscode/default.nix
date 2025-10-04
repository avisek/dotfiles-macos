{
  config,
  pkgs,
  lib,
  ...
}: let
  editors = [
    {
      package = pkgs.vscode;
      configDir = "Code";
    }
    {
      package = pkgs.code-cursor;
      configDir = "Cursor";
    }
  ];

  extensions = with pkgs.vscode-marketplace; [
    # Themes & Icons
    enkia.tokyo-night
    pkief.material-icon-theme
    zhuangtongfa.material-theme
    beardedbear.beardedtheme

    # Editor Enhancements
    cardinal90.multi-cursor-case-preserve
    tobermory.es6-string-html
    yoavbls.pretty-ts-errors
    # github.vscode-pull-request-github
    # ms-vscode.live-server
    # ritwickdey.liveserver
    # rangav.vscode-thunder-client
    # mark-wiemer.vscode-autohotkey-plus-plus

    # Language Support
    # somewhatstationery.some-sass
    esbenp.prettier-vscode
    jnoortheen.nix-ide
    tamasfe.even-better-toml
    bradlc.vscode-tailwindcss
    prisma.prisma
    # crazywolf.smali
  ];

  dotfilesPath = "${config.home.homeDirectory}/.dotfiles/home/vscode";

  configBasePath =
    if pkgs.stdenv.isDarwin
    then "Library/Application Support"
    else ".config";

  # Cursor requires special handling: vscode-with-extensions.override fails on macOS
  # due to app bundle wrapping issues. Use programs.vscode for Cursor instead.
  isCursor = editor: editor.package == pkgs.code-cursor;
  standardEditors = builtins.filter (e: !isCursor e) editors;
  cursorEditor = lib.findFirst isCursor null editors;

  mkEditorPackage = editor:
    pkgs.vscode-with-extensions.override {
      vscode = editor.package;
      vscodeExtensions = extensions;
    };

  mkEditorSettings = editor: {
    "${configBasePath}/${editor.configDir}/User/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/settings.json";
    };
    "${configBasePath}/${editor.configDir}/User/keybindings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/keybindings.json";
    };
  };
in {
  home.packages = map mkEditorPackage standardEditors;

  programs.vscode = lib.mkIf (cursorEditor != null) {
    enable = true;
    package = cursorEditor.package;
    profiles.default.extensions = extensions;
  };

  home.file = lib.mkMerge (map mkEditorSettings editors);
}
