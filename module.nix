{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.configen;
  configPath = toString cfg.configFile;
  wrappedConfigen = pkgs.writeShellScriptBin "configen" ''
    set -euo pipefail

    has_config=0
    for arg in "$@"; do
      case "$arg" in
        -c|--config|--config=*)
          has_config=1
          break
          ;;
      esac
    done

    if [ "$has_config" -eq 1 ]; then
      exec ${cfg.package}/bin/configen "$@"
    else
      exec ${cfg.package}/bin/configen --config ${lib.escapeShellArg configPath} "$@"
    fi
  '';
in {
  options.configen = {
    enable = lib.mkEnableOption "configen configuration manager";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The configen package to use";
    };

    configFile = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      description = "Path to configen.yaml used by activation script";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [wrappedConfigen];

    system.userActivationScripts.configen = ''
      ${wrappedConfigen}/bin/configen apply
    '';
  };
}
