# Configen Development Plan

## Current State

Configen works but has incomplete features and some rough edges.

### What works
- [x] ERB template rendering
- [x] Theme switching (`configen theme <name>`)
- [x] Hooks (before/after with glob patterns)
- [x] NixOS module integration
- [x] State persistence (`~/.local/state/configen/`)
- [x] Flake support (`-f ./flake.nix`)

### What's incomplete
- [ ] Wrappers instead of symlinks
- [ ] Profiles (composable feature flags)
- [ ] Hardcoded paths in hooks

---

## Phase 1: Wrappers

**Goal:** Use wrappers instead of symlinks for apps that support custom config paths.

### Why
- Cleaner than symlinks in `~/.config/`
- Config location is explicit
- Works better with Nix philosophy

### Apps that support wrappers
| App | Flag | Example |
|-----|------|---------|
| kitty | `--config` | `kitty --config $STATE/kitty/kitty.conf` |
| nvim | `-u` | `nvim -u $STATE/nvim/init.lua` |
| bat | `--config-file` | `bat --config-file $STATE/bat/config` |
| qutebrowser | `--config-py` | `qutebrowser --config-py $STATE/qutebrowser/config.py` |

### Apps that need symlinks (fallback)
| App | Reason |
|-----|--------|
| yazi | No config flag |
| niri | No config flag |
| waybar | Config path hardcoded |

### Implementation

1. **Add wrapper generation to NixOS module**
   ```nix
   configen.wrappers = {
     kitty = {
       package = pkgs.kitty;
       configPath = "kitty/kitty.conf";
     };
   };
   ```

2. **Generate wrapper scripts**
   ```bash
   #!/bin/sh
   exec /nix/store/.../kitty --config ~/.local/state/configen/current/kitty/kitty.conf "$@"
   ```

3. **Add wrappers to environment.systemPackages**

4. **Remove symlink hooks for wrapped apps**

---

## Phase 2: Clean up hardcoded paths

**Goal:** Make hooks portable.

### Current problem
```nix
script = ''
  ln -nsf /home/badenkov/.local/state/configen/current/yazi/theme.toml ...
'';
```

### Solution
Add variables to hook scripts:
```nix
script = ''
  ln -nsf $CONFIGEN_STATE/yazi/theme.toml $HOME/.config/yazi/theme.toml
'';
```

### Implementation

1. **Environment variables in hook execution**
   - `$CONFIGEN_STATE` → `~/.local/state/configen/current`
   - `$CONFIGEN_CONFIG` → config directory
   - `$HOME` → already available

2. **Update Generator#run hooks**
   ```ruby
   env = {
     "CONFIGEN_STATE" => @output_path.to_s,
     "HOME" => Dir.home
   }
   Open3.capture3(env, "bash", "-c", script)
   ```

3. **Update all hooks in modules/configen.nix**

---

## Phase 3: Profiles (Future)

**Goal:** Composable feature flags that can be combined.

### Concept
- **Themes** = mutually exclusive (light OR dark)
- **Profiles** = composable (work AND minimal AND no-animations)

### Use cases
- `work` profile: different git email, no distractions
- `minimal` profile: reduced UI, faster startup
- `presentation` profile: large fonts, high contrast

### Implementation ideas

1. **Profile structure**
   ```
   profiles/
   ├── work/
   │   └── settings.yaml
   ├── minimal/
   │   └── settings.yaml
   └── presentation/
       └── settings.yaml
   ```

2. **Merge order**
   ```
   defaults → theme → profile1 → profile2 → ...
   ```

3. **CLI**
   ```bash
   configen profile add work
   configen profile remove minimal
   configen profiles  # list active
   ```

4. **State**
   ```
   ~/.local/state/configen/
   ├── theme      # "tokyo-night"
   └── profiles   # "work\nminimal"
   ```

---

## Priority

| Phase | Priority | Effort |
|-------|----------|--------|
| Phase 1: Wrappers | High | Medium |
| Phase 2: Clean up paths | Medium | Low |
| Phase 3: Profiles | Low | High |

---

## Notes

- Keep it simple, avoid premature optimization
- Nix handles caching, no need for custom cache logic
- Watch mode is experimental, not a priority
