# Configen Plan (Simplified Home Config Management)

## Goal

`configen` manages user configs directly in `$HOME` with a static project config.
No generated config file, no symlink modes, no complex path logic.

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
```

Config file (`configen.yaml`) is static and committed to git.

Example:

```yaml
templates:
  ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
  ".config/nvim": "configs/nvim"
```

Rules:

- Key in `templates` is target path relative to `$HOME`.
- Value is source path relative to directory containing `configen.yaml`.
- Source file -> manages one target file.
- Source directory -> manages full target directory recursively.
- Source directory is `exact: true` by default (extra files in target are deleted).
- Use explicit `exact: false` to keep extra files.
- `.erb` files are rendered; non-`.erb` files are copied as-is.

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
- optional `delete` (only for explicitly managed directories and only when enabled)

---

## Safety Defaults

Keep defaults conservative:

- Do not overwrite conflicting unmanaged files silently.
- Stop apply on conflicts unless user passes `--force`.
- Do not delete extra files by default.
- If/when delete is needed, require explicit per-template setting.

Future optional extension:

```yaml
templates:
  ".config/nvim":
    source: "configs/nvim"
    exact: true
```

`exact: true` means files absent in source are removed from target directory.

---

## CLI Shape

- `configen diff` -> show planned changes in `$HOME`.
- `configen apply` -> apply planned changes.
- `configen apply --dry-run` -> simulate apply.
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

---

## Implementation Phases

1. Config format finalization
- add/lock `templates` mapping in YAML parser
- paths resolved relative to config file

2. In-memory desired state builder
- unify file + directory handling
- keep rendered content and file metadata

3. Diff + apply
- implement create/update/conflict
- dry-run output

4. Safe deletion (optional)
- add explicit `exact: true`
- delete only inside explicitly managed directories

5. Nix module cleanup
- remove mapping generation concerns
- keep only activation integration

---

## Done Criteria

- User manages configs via `configen.yaml` + `configs/`.
- No generated config mapping from nix.
- `configen apply` updates `$HOME` directly.
- Behavior is predictable, idempotent, and conflict-safe.
