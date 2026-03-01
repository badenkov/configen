# Configen

Fast home-config manager with ERB templating.

It renders files from your project and writes them directly to `$HOME`.

## Installation

```bash
# In NixOS flake
nix build .#configen
```

## Usage

```bash
# Use config from current directory (./configen.yaml)
configen diff
configen apply

# Or pass config explicitly
configen diff -c ~/dotfiles/configen.yaml
configen apply -c ~/dotfiles/configen.yaml

# Dry run
configen apply --dry-run

# Diff includes hooks that would run for this change set
configen diff

# Theme management
configen theme                  # show active and available themes
configen theme tokyo-night      # persist active theme in state for this config

# Variable overrides in state
configen get                  # show all effective variables
configen get font_size
configen get palette.bg
configen set font_size 15
configen set palette.bg "#101010"
configen set leader "*"
configen set validates.some_variable.sub_var1 "newvalue"
configen del palette.bg

# One-off override without persisting
configen diff --theme screencast
configen apply --theme screencast

# Validate templates and themes
configen validate

# Generate shell completion scripts
configen completion bash
configen completion zsh
configen completion fish
# completion includes dynamic values (themes and variable paths for get/set/del)

# Example: load completion for current shell session
source <(configen completion bash)
source <(configen completion zsh)
configen completion fish | source
```

## How it works

```
configen.yaml + configs/ -> in-memory render -> diff with $HOME -> apply changes
```

## Config structure

```yaml
themes_dir: "themes"

templates:
  ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
  ".config/nvim":
    source: "configs/nvim"

variables:
  font_size: 13
  theme:
    default:
      palette:
        bg: "#000000"
        fg: "#ffffff"
      wallpaper: "default.jpg"
    system: true

hooks:
  before:
    - description: "niri-transition"
      run: "niri msg action do-screen-transition"
      changed:
        - ".config/niri/**"
      if: "pgrep -x niri >/dev/null"
  after:
    - description: "reload-kitty"
      run: "pkill -USR1 -x kitty"
      changed:
        - ".config/kitty/**"
```

Rules:

- `templates` key is target path relative to `$HOME`.
- Template value can be:
  - string path to source file/dir relative to `configen.yaml`;
  - mapping with `source`.
- `.erb` files are rendered.
- Other files are copied as-is.
- Directory sources are synchronized exactly: extra files in target are removed.
- Theme is optional and overrides `variables`.
- `variables` supports two forms:
  - shorthand: `name: value` (equivalent to `default: value`, `system: false`);
  - definition mapping:
    - `default`: default value;
    - `system` (optional, default `false`): blocks only ad-hoc `configen set/del` for that top-level variable.
- Active theme is resolved in order:
  - `--theme` option for current command;
  - saved state file `${XDG_STATE_HOME:-~/.local/state}/configen/theme`;
  - `theme` from `configen.yaml` (optional fallback).
- Variable value priority is resolved in order:
  - `variables` from `configen.yaml`;
  - active theme overrides from `<themes_dir>/<theme>/theme.yaml`;
  - saved variable overrides `${XDG_STATE_HOME:-~/.local/state}/configen/variables.yaml`.
- `configen set` always stores `VALUE` as a string (no YAML parsing of CLI value).
- Override types are validated against the default variable value type inferred from YAML/Ruby values (`string`, `number`, `boolean`, `array`, `object`, `nil`).
- Theme file path: `<themes_dir>/<theme>/theme.yaml` (relative to `configen.yaml`).
- Theme file may be either plain variables mapping or `{ variables: ... }`.
- `configen validate` checks:
  - missing variables used in ERB templates;
  - missing source template files;
  - unknown keys in variable overrides saved in state;
  - every theme for unknown overrides (keys must exist in base `variables`).
- Hooks are optional and support:
  - `before` and `after` phases (list of hooks);
  - `description` label shown in diff/errors (optional, defaults to `run`);
  - `run` command (required);
  - `changed` glob or list of globs to run only for matching changed files;
  - `if` command as runtime condition (run only on exit code `0`).
- Hook failures do not stop other hooks, but are reported as apply errors.
- Hooks are not executed in `--dry-run`.

Theme example (`themes/tokyo-night/theme.yaml`):

```yaml
font_size: 15
palette:
  bg: "#1a1b26"
  fg: "#c0caf5"
```

Template example:

```erb
# kitty.conf.erb
font_size <%= font_size %>
```

## NixOS module

Nix can be used as orchestration only:
- install `configen`,
- run `configen apply -c /path/to/configen.yaml` during activation.

With this module enabled, a system wrapper `configen` is installed:
- by default it injects `--config <configen.configFile>`;
- if you pass `-c`/`--config` explicitly, your value takes precedence.
