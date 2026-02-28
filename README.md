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
```

## How it works

```
configen.yaml + configs/ -> in-memory render -> diff with $HOME -> apply changes
```

## Config structure

```yaml
templates:
  ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
  ".config/nvim":
    source: "configs/nvim"
    exact: true

variables:
  font_size: 13
```

Rules:

- `templates` key is target path relative to `$HOME`.
- Template value can be:
  - string path to source file/dir relative to `configen.yaml`;
  - mapping with `source` and optional `exact`.
- `.erb` files are rendered.
- Other files are copied as-is.
- For directory sources, `exact` is `true` by default (extra target files are removed).
- Set `exact: false` to keep extra files in target.

Template example:

```erb
# kitty.conf.erb
font_size <%= font_size %>
```

## NixOS module

Nix can be used as orchestration only:
- install `configen`,
- run `configen apply -c /path/to/configen.yaml` during activation.
