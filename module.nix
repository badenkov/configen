{
  config,
  lib,
  ...
}: let
  cfg = config.configen;
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
      ${cfg.package}/bin/configen apply --config ${lib.escapeShellArg (toString cfg.configFile)}
    '';
  };
}
