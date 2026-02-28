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

# Theme management
configen theme                  # show active and available themes
configen theme tokyo-night      # persist active theme in state for this config

# One-off override without persisting
configen diff --theme screencast
configen apply --theme screencast
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
  - saved state file under `${XDG_STATE_HOME:-~/.local/state}/configen/themes/` (scoped per config path);
  - `theme` from `configen.yaml` (optional fallback).
- Theme file path: `<themes_dir>/<theme>/theme.yaml` (relative to `configen.yaml`).
- Theme file may be either plain variables mapping or `{ variables: ... }`.

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
