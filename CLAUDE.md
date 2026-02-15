# Claude Code Instructions for Configen

## Project Overview

Configen is a Ruby CLI tool for managing configuration files with ERB templating and theme support. It integrates with NixOS but can work standalone.

## Tech Stack

- **Language:** Ruby 3.4
- **CLI framework:** Thor
- **Templating:** ERB
- **Config formats:** JSON, YAML, TOML (via tomlib)
- **File watching:** listen gem
- **Autoloading:** Zeitwerk
- **Package manager:** Bundler + Nix (bundlerEnv)

## Project Structure

```
configen/
├── bin/configen           # Entry point
├── lib/
│   ├── configen.rb        # Main module, requires
│   └── configen/
│       ├── cli.rb         # Thor CLI commands
│       ├── config.rb      # Config loading (files, flakes)
│       ├── environment.rb # Orchestrates rendering
│       ├── generator.rb   # Template rendering + hooks
│       ├── variables.rb   # Theme variable loading
│       ├── view.rb        # (unused?)
│       └── erb/
│           ├── template.rb
│           └── template_context.rb
├── test/                  # Minitest tests
├── default.nix            # Nix package definition
├── Gemfile                # Ruby dependencies
└── gemset.nix             # Nix gem lockfile
```

## Key Classes

### `Configen::CLI` (cli.rb)
Thor-based CLI. Commands:
- `apply` - render templates with current theme
- `theme [name]` - get/set theme
- `themes` - list available themes
- `watch` - watch for changes (experimental)
- `version` - show config info

### `Configen::Config` (config.rb)
Loads configuration from:
1. Flake (`-f ./flake.nix` → runs `nix build`)
2. Config file (`--config path`)
3. XDG config dirs (default)

Key methods:
- `templates` - hash of output_path → template_path
- `hooks` - array of {pattern, script, when}
- `themes_path` - path to themes directory
- `state_path` - `~/.local/state/configen`

### `Configen::Environment` (environment.rb)
Orchestrates the apply process:
1. Loads current theme from state
2. Sets up hooks on generator
3. Calls `generator.render(templates, variables)`
4. Saves theme to state on success

### `Configen::Generator` (generator.rb)
Core rendering logic:
1. Calculate previous state (SHA256 hashes)
2. Render all templates
3. Diff: to_create, to_update, to_delete
4. Run before hooks
5. Write files to output_path
6. Run after hooks

### `Configen::Variables` (variables.rb)
Loads theme variables from directory:
- `settings.yaml` - main config
- `*.toml`, `*.yaml` - additional files merged in

## NixOS Integration

The NixOS module (`modules/configen.nix`) defines:
- `configen.templates` - attrset of templates
- `configen.hooks` - list of hooks
- `configen.themes_path` - path to themes
- `configen.defaults` - default variables

It generates `config.json` in two modes:
1. **Absolute paths** (nixos-rebuild): `/nix/store/xxx-template.erb`
2. **Relative paths** (development): `modules/templates/template.erb`

## Development

```bash
cd configen
direnv allow  # or: devenv shell

# Run tests
rake test

# Run CLI
bin/configen version
bin/configen apply -f ../flake.nix
```

## Testing

Tests use Minitest with fixtures in `test/fixtures/files/`.

```bash
rake test
ruby -Ilib:test test/configen/generator_test.rb
```

## Common Tasks

### Adding a new CLI command
1. Add method to `lib/configen/cli.rb`
2. Use `build_env` helper to get config and environment

### Adding template format support
1. Add case in `Generator#render_template`
2. Create renderer method like `render_erb`

### Modifying config schema
1. Update `Config::DEFAULTS`
2. Update `normalize_values` if paths need expansion
3. Update NixOS module `modules/configen.nix`
