{
  pkgs,
  lib,
  ...
}: {
  programs.zsh =
    {
      enable = true;
    }
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellInit = ''
        zsh-newuser-install() { :; }
      '';
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      enableAutosuggestions = true;
      enableSyntaxHighlighting = true;
    };

  users = lib.optionalAttrs pkgs.stdenv.isLinux {
    defaultUserShell = pkgs.zsh;
  };

  environment.shellAliases = let
    rebuild =
      if pkgs.stdenv.isDarwin
      then "darwin-rebuild"
      else "nixos-rebuild";
    test =
      if pkgs.stdenv.isDarwin
      then "check"
      else "test";
    hook = "eval \"$_PRE_NRS\" 2>/dev/null;";
  in {
    nrs = "${hook} sudo ${rebuild} switch --flake ~/.dotfiles --impure";
    nrt = "${hook} sudo ${rebuild} ${test} --flake ~/.dotfiles --impure";
    nrb = "${hook} sudo ${rebuild} boot --flake ~/.dotfiles --impure";
    nrbr = "nrb && reboot";
    nfu = "nix flake update --flake ~/.dotfiles --impure";
    ngc = "sudo nix-collect-garbage -d && nrs";
    ngcr = "ngc && reboot";
    nrl = "sudo ${rebuild} --list-generations";
  };
}
