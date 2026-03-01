{
  config,
  lib,
  ...
}: let
  cfg = config.configen;
  configPath = toString cfg.configFile;
  configDir = builtins.dirOf configPath;
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
    system.userActivationScripts.configen = ''
      mkdir -p "$HOME/.config"
      ln -sfn ${lib.escapeShellArg configDir} "$HOME/.config/configen"
      ${cfg.package}/bin/configen apply
    '';
  };
}
