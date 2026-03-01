# AGENT

## Project
- `configen` is a Ruby CLI for managing user dotfiles in `$HOME`.
- Sources are declared in `configen.yaml` via `templates` mapping (target path -> source path).
- `.erb` files are rendered with variables/theme variables; non-ERB files are copied.
- Directory sources are synced exactly (extra files in target are removed).

## Main Paths
- CLI entrypoint: `bin/configen` (dev) and `exe/configen`.
- Core code: `lib/configen/*.rb`.
- Tests: `test/**/*_test.rb`.
- Playground for manual checks: `playground/`.

## Config Model
- Primary config file: `configen.yaml` (passed with `-c/--config` or auto-discovered in cwd).
- Templates live under `configs/` (relative to config file).
- Themes are directories under `themes_dir`, each with `theme.yaml`.
- Active theme is dynamic (set by `configen theme <name>`) and stored in XDG state.

## Hooks
- Hooks support `before` and `after` phases.
- Each hook can use: `description`, `run`, `changed`, `if`.
- Hook failures are reported but do not stop other hooks.
- `configen diff` should show planned hook runs for the current change set.

## How To Work Here
- Prefer running via dev shell command `configen` for manual checks.
- Run tests with `bundle exec rake test` (or `bundle exec ruby -Itest <test_file>`).
- Run lint with `bundle exec rubocop`.
- Keep changes minimal and consistent with existing simple/explicit style.
