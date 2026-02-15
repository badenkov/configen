{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.configen;

  hookType = lib.types.submodule {
    options = {
      pattern = lib.mkOption {
        default = "*";
        type = lib.types.str;
        description = "Glob pattern to match files";
      };
      script = lib.mkOption {
        type = lib.types.str;
        description = "Bash script to execute";
      };
      when = lib.mkOption {
        default = "after";
        type = lib.types.enum ["before" "after"];
        description = "When to run the hook";
      };
    };
  };
in {
  options.configen = {
    enable = lib.mkEnableOption "configen configuration manager";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The configen package to use";
    };

    templates = lib.mkOption {
      default = {};
      type = lib.types.attrsOf lib.types.path;
      description = "Attribute set of output paths to template paths";
    };

    hooks = lib.mkOption {
      default = [];
      type = lib.types.listOf hookType;
      description = "List of hooks to run when configs change";
    };

    themes_path = lib.mkOption {
      type = lib.types.path;
      description = "Path to themes directory";
    };

    defaults = lib.mkOption {
      default = {};
      type = lib.types.attrsOf lib.types.str;
      description = "Default variables available in templates";
    };

    out = lib.mkOption {
      type = lib.types.anything;
      description = "Function to generate config.json with relative paths";
    };
  };

  config = lib.mkIf cfg.enable {
    configen.out = let
      relativize = root: path: lib.removePrefix "${root}/" (toString path);
      relativizedFiles = root: templates:
        lib.mapAttrs (_: v: (relativize root) v)
        templates;

      config_file = root:
        pkgs.writers.writeJSON "config.json" {
          templates = relativizedFiles root cfg.templates;
          hooks = cfg.hooks;
          themes_path = lib.removePrefix "${root}/" (toString cfg.themes_path);
          defaults = cfg.defaults;
        };
    in
      root: config_file root;

    system.userActivationScripts.configen = let
      config_file = pkgs.writers.writeJSON "config.json" {
        templates = cfg.templates;
        hooks = cfg.hooks;
        themes_path = cfg.themes_path;
        defaults = cfg.defaults;
      };
    in ''
      rm -rf $XDG_CONFIG_HOME/configen
      mkdir -p $XDG_CONFIG_HOME/configen
      ln -nsf ${config_file} $XDG_CONFIG_HOME/configen/config.json
      ${cfg.package}/bin/configen apply --config ${config_file} > $HOME/configen.log 2>&1
    '';
  };
}
