# PLAN

Prioritized changes. Each item is independently shippable; order within a priority
band is the suggested implementation order.

## 1. Seeds + `configen pull` (high)

Files that configen writes once and then hands over to the program that owns them
(programs that rewrite their own config). Home becomes the source of truth after
the first write; `pull` harvests changes back into the repo.

- New top-level config section:

  ```yaml
  seeds:
    .config/qbittorrent/qBittorrent.conf: configs/qbittorrent/qBittorrent.conf
  ```

- Semantics:
  - `apply` writes a seed only if the target does not exist. Existing targets are
    never touched and never reported as drift.
  - `diff` shows pending seeds as `SEED <path>` lines.
  - Seed sources must be plain files — `.erb` is rejected at config load
    (reverse-rendering is impossible; if the app owns the file, templating it is
    pointless anyway).
  - Seeds do not participate in manifest pruning and do not match hook `changed`
    globs (the app changes the file, not apply — nothing to react to).
- New command `configen pull`:
  - copies current `$HOME` content back into the source path for every seed whose
    content differs from the repo;
  - `--dry-run` lists what would be copied;
  - after pull, `git diff` in the dotfiles repo shows what the app changed.
- `validate` checks: seed source exists, is not `.erb`, seed target does not
  collide with a `templates` target.
- No new state: "target file exists" is the only fact needed.

## 2. File permissions + atomic writes (high)

- Mapping form of a template spec gets `mode`:

  ```yaml
  templates:
    .ssh/config:
      source: configs/ssh/config.erb
      mode: "600"
  ```

  - Octal string. For directory sources it applies to every produced file.
  - Shorthand form stays unchanged for the common case.
- Executable bit is inherited from the source file by default (git tracks exactly
  this one bit), so committed `chmod +x configs/theme.sh.erb` yields an executable
  `~/.config/theme.sh` with zero config.
- `diff`/`apply` detect mode drift: same content but wrong mode is an `UPDATE`.
- Writes become atomic: render to a temp file in the target directory, `chmod`,
  then `rename` over the destination.
- Applies to seeds too (initial write only).

## 3. NixOS module: re-run apply on `nixos-rebuild switch` (high, small)

The systemd unit text does not change when only the config directory content
changes, so `switch` never restarts the service — new config applies only on next
boot.

- Add `restartTriggers` (via `X-Restart-Triggers` / `systemd.services.<name>.restartTriggers`)
  containing the config directory store path so any content change re-runs
  `configen apply`.

## 4. Variable schema formalization + typed `set` (medium)

The default value in `variables` is the canonical schema ("schema by example"),
recursively. Formal rules:

- `Value ::= Scalar (string | number | boolean) | Array | Object`
- Objects are closed (overrides may only touch existing paths — already enforced)
  and deep-merge; scalars and arrays are replaced wholesale.
- Arrays are opaque leaves: element types are not checked, no per-element `set`.
- `null` default = untyped leaf (accepts any scalar).
- `configen set` coerces the CLI string by the target leaf type: number is parsed,
  boolean accepts only `true`/`false`, string is taken verbatim; `set` on object
  or array paths is rejected. Invalid input fails at `set` time, not at next diff.

This fixes a real inconsistency: `set` currently stores every value as a string
(`normalize_override_value` -> `to_s`), while override validation compares types
against defaults — so `configen set font_size 15` (the README example) writes
`"15"` and breaks subsequent `diff`/`apply` with a type mismatch until the state
file is edited by hand.

Document the rules in README as the single source of truth for the type system.

## 5. Extract shell completion out of `cli.rb` (medium)

~400 of 550 lines of `lib/configen/cli.rb` are completion script builders.

- Move to `lib/configen/cli/completion.rb` (module included into `Configen::CLI`,
  or a plain object the CLI delegates to).
- No behavior change; existing `cli_test.rb` must pass as-is.
- Later decision (out of scope here): whether to keep all three shells.

## 6. Cleanups (low)

- Remove `system:` variable definitions: the `variable_definitions` machinery,
  the `set`/`del` guard, and the completion `--mode` filtering. Its only effect is
  blocking ad-hoc `set`/`del`; not worth a concept.
- Collapse the `TemplateContext` / `StrictOpenStruct` duplication (both implement
  `method_missing` + did_you_mean over the same variables); drop dead commented
  code and the unused private `sugest` method.

## Not planned (revisit later)

- **Profiles** (stackable, toggleable override sets on top of the active theme —
  zen-mode, screencast, battery-saver). The primitive already exists: a boolean
  variable + `configen set`. Revisit when 2–3 such toggles exist in practice and
  batching them under a name starts to hurt. Design sketch if/when needed:
  `profiles/<name>.yaml`, `configen profile on|off <name>`, merge order
  `variables -> theme -> profiles (activation order) -> set overrides`.
- **Themes layout**: keep per-theme directories (`themes/<name>/theme.yaml`) as-is.
- **base16/base24 ingestion**: when adopting base16 scheme files as themes, teach
  the theme loader to tolerate their metadata keys (`scheme`, `author`) — defer
  until actually adopting base16.
