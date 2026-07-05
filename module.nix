{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.configen;

  enabledUsers = lib.filterAttrs (_: userCfg: userCfg.enable) cfg.users;

  mkUserConfig = name: userCfg: let
    configPath = toString userCfg.configFile;
    configDir = builtins.dirOf configPath;
    userConfig = config.users.users.${name} or null;
    homeDirectory =
      if userConfig != null && userConfig ? home
      then userConfig.home
      else "/home/${name}";
    activationScript = pkgs.writeShellScript "configen-activate-${name}" ''
      set -eu
      exec ${userCfg.package}/bin/configen apply
    '';
    serviceName = "configen-${name}";
  in {
    etc."configen/users/${name}/current".source = configDir;

    systemdService.${serviceName} = {
      description = "Configen activation for ${name}";
      wantedBy = ["multi-user.target"];
      wants = ["nix-daemon.socket"];
      after = ["nix-daemon.socket"];
      before = ["systemd-user-sessions.service"];
      unitConfig.RequiresMountsFor = homeDirectory;
      serviceConfig = {
        Type = "oneshot";
        User = name;
        Environment = "HOME=${homeDirectory}";
        ExecStart = activationScript;
      };
    };
  };

  userConfigs = lib.mapAttrsToList mkUserConfig enabledUsers;
in {
  options.configen = {
    enable = lib.mkEnableOption "configen configuration manager";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The default configen package to use";
    };

    users = lib.mkOption {
      default = {};
      description = "Per-user configen configurations";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "configen for this user" // {
            default = true;
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = cfg.package;
            defaultText = lib.literalExpression "config.configen.package";
            description = "The configen package to use for this user";
          };

          configFile = lib.mkOption {
            type = lib.types.either lib.types.path lib.types.str;
            description = "Path to this user's configen.yaml";
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = lib.mkMerge (map (userCfg: userCfg.etc) userConfigs);
    systemd.services = lib.mkMerge (map (userCfg: userCfg.systemdService) userConfigs);
  };
}
