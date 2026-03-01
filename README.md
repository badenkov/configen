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

# One-off override without persisting
configen diff --theme screencast
configen apply --theme screencast

# Validate templates and themes
configen validate
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
  palette:
    bg: "#000000"

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
- Active theme is resolved in order:
  - `--theme` option for current command;
  - saved state file `${XDG_STATE_HOME:-~/.local/state}/configen/theme`;
  - `theme` from `configen.yaml` (optional fallback).
- Theme file path: `<themes_dir>/<theme>/theme.yaml` (relative to `configen.yaml`).
- Theme file may be either plain variables mapping or `{ variables: ... }`.
- `configen validate` checks:
  - missing variables used in ERB templates;
  - missing source template files;
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
