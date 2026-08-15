# Configen

Generates the config files in your `$HOME` from a git repository, with ERB templating and themes.

**Scope.** Configen manages files under `$HOME` and nothing else. Packages, services and everything
outside the home directory are NixOS's job; configen only renders per-user configuration that has to
change without a rebuild — themes, font sizes, per-machine tweaks. Targets are always paths relative
to `$HOME`; absolute paths are not supported by design.

## Model

```
configen.yaml + configs/  ->  render in memory  ->  compare with $HOME  ->  apply
```

Three ideas are enough to predict what configen will do:

1. **The repository is the source of truth.** Every apply renders all templates from scratch and makes
   `$HOME` match the result. There is no incremental state to drift.
2. **Configen only touches files it created.** A file it has never written is never overwritten without
   `--force` (see [Ownership](#ownership)).
3. **Files an application rewrites itself are seeds**, not templates: written once, then owned by the
   app, and harvested back into the repository with `configen pull`.

## Install

```bash
nix build .#configen          # in a NixOS flake
```

## Quick start

```bash
cd ~/dotfiles                 # directory containing configen.yaml
configen diff                 # what would change
configen diff -p              # ...including the actual content diff
configen apply                # make $HOME match the repository
```

On a machine that already has hand-written configs, the first apply reports them as `ADOPT` and
refuses to continue. Inspect them with `configen diff -p`, then take ownership once:

```bash
configen apply --force
```

## Commands

| Command | Purpose |
| --- | --- |
| `configen diff [-p]` | Show the planned changes; `-p`/`--patch` adds a unified content diff |
| `configen apply` | Render templates and write seeds; `--dry-run`, `--force` |
| `configen pull` | Copy changed seed files from `$HOME` back into the repository |
| `configen validate` | Check templates, seeds, themes and saved overrides without touching `$HOME` |
| `configen theme [NAME]` | Show themes, or persist the active one |
| `configen get [VAR]` | Show all effective variables, or one value |
| `configen set VAR VALUE` | Persist a variable override |
| `configen del VAR` | Remove a persisted override |
| `configen completion SHELL` | Print a completion script for `bash`, `zsh` or `fish` |
| `configen version` | Version, config path and state path |

Every command fails with a non-zero exit status when it reports errors.

Common options: `-c PATH` picks the config file explicitly, `--theme NAME` applies a theme for one
command without persisting it.

```bash
configen diff -c ~/dotfiles/configen.yaml
configen apply --theme screencast
configen completion fish | source
```

Config file resolution order: `-c PATH`, then `./configen.yaml`, then
`/etc/configen/users/$USER/current/configen.yaml`.

## configen.yaml

```yaml
themes_dir: "themes"          # optional, defaults to "themes"
theme: "tokyo-night"          # optional fallback theme

templates:
  ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
  ".config/nvim":
    source: "configs/nvim"
  ".config/herdr":
    source: "configs/herdr"
    ignore:
      - "plugins/"
      - "plugins.json"
      - "*.log"
  ".ssh/config":
    source: "configs/ssh/config.erb"
    mode: "600"

seeds:
  ".config/qbittorrent/qBittorrent.conf": "configs/qbittorrent/qBittorrent.conf"

variables:
  font_size: 13
  palette:
    bg: "#000000"
    fg: "#ffffff"

hooks:
  after:
    - description: "reload-kitty"
      run: "pkill -USR1 -x kitty"
      changed: [".config/kitty/**"]
```

Keys of `templates` and `seeds` are target paths relative to `$HOME`; values are source paths relative
to `configen.yaml`.

### Templates

A template value is either a source path or a mapping with `source` and the optional keys below.

- `.erb` files are rendered with the current variables; the `.erb` suffix is dropped in the target.
  Every other file is copied verbatim.
- **Directory sources are synchronized exactly**: files in the target that the source does not produce
  are deleted (except ignored ones).
- `mode` is an octal string (`"600"`). Without it a generated file gets `0644`, or `0755` when the
  source file is executable — so `chmod +x` in git is enough to produce an executable target.
  Content that matches but a mode that does not is reported as `UPDATE`.
- `ignore` (directory sources only) excludes paths from rendering, from exact synchronization and from
  the manifest. Adding a pattern releases an already generated file instead of deleting it, which is
  how an application takes over a subdirectory. An explicit template or seed may still target a path
  inside an ignored subtree.

### Seeds

A seed is a plain file (never `.erb`) that configen writes **only if the target does not exist**.
After that the application owns it: it is never updated, never reported as drift, never pruned.

`configen pull` copies changed seed targets from `$HOME` back to their source files, so `git diff` in
the repository shows what the application changed.

### Path patterns

`ignore` and hook `changed` use one glob dialect. `ignore` patterns are relative to the template
target directory, `changed` patterns are relative to `$HOME`.

| Pattern | Matches |
| --- | --- |
| `plugins/` or `plugins/**` | the whole subtree, at any depth |
| `**` | everything |
| `*.log` | only at the root of the scope |
| `**/*.log` | at any depth |
| `plugins.json` | exactly that path |

### Variables and themes

Values are resolved in three layers, each overriding the previous one:

1. `variables` in `configen.yaml` — the defaults, and the schema;
2. the active theme, `<themes_dir>/<theme>/theme.yaml`;
3. persisted overrides from `configen set`.

The active theme is `--theme`, else the theme saved by `configen theme NAME`, else `theme` from
`configen.yaml`. A theme file is either a plain variables mapping or `{ variables: ... }`.

```yaml
# themes/tokyo-night/theme.yaml
font_size: 15
palette:
  bg: "#1a1b26"
```

**The default value defines the schema**, recursively:

- strings, numbers and booleans are typed leaves; an override must keep the type;
- objects are closed and deep-merged — an override may only use paths that exist in the defaults;
- arrays are opaque leaves, replaced as a whole; `configen set` cannot touch them or their elements;
- `null` is an untyped leaf that accepts any scalar.

`configen set` coerces its argument to the leaf type (numbers parsed, booleans only `true`/`false`,
strings verbatim) and rejects object and array paths. Themes and saved overrides are validated against
the same schema before every diff and apply.

```bash
configen set font_size 15
configen set palette.bg "#101010"
configen del palette.bg
```

### Templates and ERB

Variables are available by name; an undefined name aborts the render with a suggestion instead of
producing a broken config. Nested objects are addressed with dots, and can be iterated:

```erb
font_size <%= font_size %>
background <%= palette.bg %>

<% palette.each do |name, color| %>
color_<%= name %> <%= color %>
<% end %>
```

`each`, `to_h`, `keys`, `key?`, `dig`, `[]` and `empty?` are available on every object; any other name
is looked up as a variable.

### Hooks

```yaml
hooks:
  before:
    - description: "niri-transition"
      run: "niri msg action do-screen-transition"
      changed: [".config/niri/**"]
      if: "pgrep -x niri >/dev/null"
  after:
    - "systemctl --user restart waybar"
```

- `run` is required; a bare string is shorthand for `run` with the same `description`.
- `changed` limits the hook to change sets touching those paths. Without it the hook runs on every
  apply. Seed writes never match, since the application — not configen — owns those files.
- `if` runs the hook only when the command exits `0`.
- Hooks are listed by `configen diff`, skipped in `--dry-run`, and a failing hook does not stop the
  others but does make `apply` fail.

## Ownership

`apply` records every file it writes in a manifest, and that manifest decides what configen may
overwrite or delete.

| Report | Meaning |
| --- | --- |
| `CREATE` | target does not exist |
| `UPDATE` | configen wrote this file before; content or mode changed |
| `ADOPT` | the target exists but configen never wrote it — needs `--force` |
| `DELETE` | configen wrote it before, and no template produces it now |
| `SEED` | first write of a seed |
| `CONFLICT` | the path cannot be written: a directory, a non-regular file, or a parent that is a file |

Safety rules:

- an existing file or symlink that configen did not create is `ADOPT`: `apply` refuses until
  `--force` is passed, and `--force` replaces the content;
- an unmanaged file whose content already matches is simply adopted, since nothing is lost;
- a stale file that was edited by hand after configen wrote it is a `CONFLICT`, and is preserved
  rather than deleted;
- writes are atomic — a temporary file in the target directory, then a rename.

## State

Per-machine, outside the repository, in `${XDG_STATE_HOME:-~/.local/state}/configen`:

| File | Contents |
| --- | --- |
| `theme` | active theme |
| `variables.yaml` | overrides from `configen set` |
| `rendered.yaml` | manifest of generated files and their hashes |

## NixOS module

Nix does orchestration only: install `configen`, publish the config directory at
`/etc/configen/users/<user>/current`, and run `configen apply` as the user in a systemd activation
service on every rebuild.

```nix
{
  configen = {
    enable = true;
    users.badenkov.configFile = ./configen.yaml;
  };
}
```
