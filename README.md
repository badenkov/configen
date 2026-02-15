# Configen

Fast configuration file manager with ERB templating and theme support. Designed for NixOS but works standalone.

## Why?

- **Faster than home-manager** - change a template, run `configen apply`, done in milliseconds
- **Theme switching** - switch color themes on the fly with `configen theme <name>`
- **Nix integration** - templates live next to NixOS modules, not in a separate dotfiles directory
- **Hooks** - run commands when specific configs change (reload app, create symlinks, etc.)

## Installation

```bash
# In NixOS flake
nix build .#configen
```

## Usage

```bash
# Apply configs using flake
configen apply -f ./flake.nix

# Apply using config file
configen apply --config ~/.config/configen/config.json

# List available themes
configen themes

# Show current theme
configen theme

# Switch theme
configen theme tokyo-night-storm

# Show version and config info
configen version
```

## How it works

```
┌─────────────────────────────────────────────────────────┐
│ configen apply -f ./flake.nix                           │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ 1. nix build .#config → config.json                     │
│    (templates, hooks, themes_path)                      │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Load theme from ~/.local/state/configen/theme        │
│    (or "default" if not set)                            │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Render templates with theme variables                │
│    Output: ~/.local/state/configen/current/             │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Run hooks (before/after) based on changed files      │
└─────────────────────────────────────────────────────────┘
```

## Config structure

```json
{
  "templates": {
    "kitty/kitty.conf": "modules/templates/kitty.conf.erb",
    "waybar/style.css": "modules/templates/waybar/style.css.erb"
  },
  "themes_path": "themes_ng",
  "hooks": [
    {
      "pattern": "kitty/*",
      "script": "pkill -USR1 kitty || true",
      "when": "after"
    }
  ],
  "defaults": {
    "greeting": "Welcome!"
  }
}
```

## Theme structure

```
themes_ng/
├── tokyo-night-storm/
│   ├── settings.yaml    # Main variables
│   └── colors.toml      # Additional variables
├── gruvbox-dark/
│   └── settings.yaml
└── catppuccin/
    └── settings.yaml
```

Variables from theme files are available in ERB templates:

```erb
# kitty.conf.erb
foreground <%= colors.foreground %>
background <%= colors.background %>
```

## State

```
~/.local/state/configen/
├── theme              # Current theme name
└── current/           # Rendered configs
    ├── kitty/
    ├── waybar/
    └── ...
```

## NixOS module

See `modules/configen.nix` for NixOS integration. It generates `config.json` with:
- Absolute paths (for nixos-rebuild)
- Relative paths (for development via `nix build .#config`)
