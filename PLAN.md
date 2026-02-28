# Configen Plan (Simplified Home Config Management + Themes)

## Goal

`configen` manages user configs directly in `$HOME` with a static project config.
No generated config file, no symlink modes, no complex path logic.
Theme support is first-class. Profiles are intentionally postponed.

---

## Directory and Config Format

Project layout:

```text
<project-root>/
  configen.yaml
  configs/
    kitty/
      kitty.conf.erb
    nvim/
      init.lua
  themes/
    gruvbox-dark/
      theme.yaml
    gruvbox-light/
      theme.yaml
    gruvbox-screencast/
      theme.yaml
```

Config file (`configen.yaml`) is static and committed to git.

Example:

```yaml
variables:
  font_family: "JetBrains Mono"
  font_size: 12

themes_dir: "themes"

templates:
  ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
  ".config/nvim":
    source: "configs/nvim"
```

Rules:

- Key in `templates` is target path relative to `$HOME`.
- Value is source path relative to directory containing `configen.yaml`.
- Source file -> manages one target file.
- Source directory -> manages full target directory recursively.
- Source directory is always exact (extra files in target are deleted).
- `.erb` files are rendered; non-`.erb` files are copied as-is.
- Theme variables override base `variables`.

Theme rules:

- `themes_dir` is resolved relative to `configen.yaml`.
- active theme is selected dynamically (`configen theme <name>`) and stored in state.
- theme state is stored under XDG state path and scoped per config path.
- optional `theme` in config may be fallback default.
- one directory = one theme (keep light/dark as separate theme names).
- Theme files contain only variables/overrides.

Variable precedence:

1. `variables` from `configen.yaml`
2. active theme variables

---

## Apply Model

Single mode only: write/copy files into `$HOME`.

Flow:

1. Parse `configen.yaml`.
2. Build desired file set in memory (render + collect).
3. Compute diff against current `$HOME`.
4. Apply changes.

Operations:

- `create`
- `update`
- `conflict`
- `delete` for managed directories

---

## Safety Defaults

Keep defaults conservative:

- Do not overwrite conflicting unmanaged files silently.
- Stop apply on conflicts unless user passes `--force`.
- Keep deletion scoped strictly to explicitly managed target directories.
- Never delete outside managed roots.

---

## CLI Shape

- `configen diff` -> show planned changes in `$HOME`.
- `configen apply` -> apply planned changes.
- `configen apply --dry-run` -> simulate apply.
- `configen theme [NAME]` -> show/set active theme in state.
- Config path resolution:
  - explicit via CLI arg (for example `-c /path/to/configen.yaml`);
  - fallback: look for `./configen.yaml` in current working directory.

(`render` command may remain internal implementation detail and not required as a user-facing step.)

---

## NixOS / Home Manager Role

Nix module still has value, but much smaller scope.

Use module for:

- installing `configen`,
- passing path to `configen.yaml`,
- running `configen apply` in activation.

Do not use module for:

- generating template mapping,
- generating per-file symlink hooks.

So nix becomes orchestration, and `configen.yaml` becomes the source of truth.

Suggested activation idea:

1. optional check: `configen diff --fail-on-conflict`
2. activation: `configen apply`

Theme and activation:

- nix can choose active theme by calling `configen theme <name>` before activation apply, or by passing CLI override.
- config content (templates, variables, themes) remains in repo; nix only orchestrates execution.

---

## Profiles (Deferred)

Current decision: do not implement profiles now.

Reason:

- no clear real-world use cases yet beyond theme-like overrides;
- avoid premature complexity in merge and precedence logic.

Future path (if needed):

- add `profiles_dir` + `profiles: []`;
- apply after theme as stackable overrides;
- precedence would become: base variables -> theme -> profiles (left to right).

---

## Implementation Phases

1. Config format finalization
- add/lock `templates` mapping in YAML parser
- paths resolved relative to config file
- add/lock `variables`, `themes_dir`, `theme`

2. In-memory desired state builder
- unify file + directory handling
- keep rendered content and file metadata
- merge variables with active theme before render

3. Diff + apply
- implement create/update/conflict
- dry-run output

4. Safe deletion
- keep directory synchronization strict by default and only mode
- delete only inside explicitly managed directories

5. Nix module cleanup
- remove mapping generation concerns
- keep only activation integration

6. Profiles (optional future)
- introduce only after concrete use-cases appear
- keep backward-compatible config format

---

## Done Criteria

- User manages configs via `configen.yaml` + `configs/`.
- No generated config mapping from nix.
- `configen apply` updates `$HOME` directly.
- Behavior is predictable, idempotent, and conflict-safe.
- User can switch one active theme via `theme` + `themes_dir`.
- Profiles are not required for initial release of this model.
