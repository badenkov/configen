# frozen_string_literal: true

require "test_helper"

class Configen::ConfigTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @system_config_root = @root.join("etc", "configen")
      @env = {
        "XDG_STATE_HOME" => @home.join(".local", "state").to_s,
        "USER" => "testuser"
      }
      super
    end
  end

  def test_defaults_without_config
    cfg = Configen::Config.new(env: @env, home: @home)

    assert_nil cfg.config_path
    assert_empty cfg.templates
    assert_empty cfg.seeds
    assert_instance_of Configen::StrictOpenStruct, cfg.variables
    assert_equal @home.join(".local", "state", "configen").to_s, cfg.state_path
  end

  def test_loads_yaml_and_resolves_template_paths_relative_to_config
    project = @root.join("dotfiles")
    project.join("configs", "kitty").mkpath
    project.join("configs", "kitty", "kitty.conf.erb").write("kitty <%= value %>")
    project.join("configs", "nvim").mkpath
    project.join("configs", "nvim", "init.lua").write("vim.o.number = true")

    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
        ".config/nvim":
          source: "configs/nvim"
      variables:
        value: "ok"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    kitty = cfg.templates.fetch(".config/kitty/kitty.conf")
    nvim = cfg.templates.fetch(".config/nvim")

    assert_equal project.join("configen.yaml"), cfg.config_path
    assert_equal project.join("configs", "kitty", "kitty.conf.erb"), kitty.source
    assert_equal project.join("configs", "nvim"), nvim.source
    assert_equal "ok", cfg.variables.value
  end

  def test_loads_template_mode_from_mapping
    project = @root.join("dotfiles-template-mode")
    project.join("configs", "ssh").mkpath
    project.join("configs", "ssh", "config.erb").write("Host *\n")
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".ssh/config":
          source: "configs/ssh/config.erb"
          mode: "600"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    spec = cfg.templates.fetch(".ssh/config")

    assert_equal project.join("configs", "ssh", "config.erb"), spec.source
    assert_equal 0o600, spec.mode
  end

  def test_rejects_invalid_template_mode
    project = @root.join("dotfiles-template-mode-invalid")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".ssh/config":
          source: "configs/ssh/config.erb"
          mode: "rw-------"
    YAML

    error = assert_raises RuntimeError do
      Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    end
    assert_match(/Template mode must be an octal string/, error.message)
  end

  def test_loads_directory_template_ignore_patterns
    project = @root.join("dotfiles-template-ignore")
    project.join("configs", "herdr").mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/herdr":
          source: "configs/herdr"
          ignore:
            - "plugins/"
            - "plugins.json"
            - "*.log"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    assert_equal ["plugins/", "plugins.json", "*.log"], cfg.templates.fetch(".config/herdr").ignore
  end

  def test_rejects_unsafe_template_ignore_pattern
    project = @root.join("dotfiles-template-ignore-invalid")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/herdr":
          source: "configs/herdr"
          ignore: "../plugins"
    YAML

    error = assert_raises RuntimeError do
      Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    end
    assert_match(/must be relative and must not include `\.\.`/, error.message)
  end

  def test_loads_seed_paths_relative_to_config
    project = @root.join("dotfiles-seeds")
    project.join("configs", "qbittorrent").mkpath
    project.join("configs", "qbittorrent", "qBittorrent.conf").write("[Preferences]\n")
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      seeds:
        ".config/qbittorrent/qBittorrent.conf": "configs/qbittorrent/qBittorrent.conf"
      variables: {}
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    seed = cfg.seeds.fetch(".config/qbittorrent/qBittorrent.conf")

    assert_equal project.join("configs", "qbittorrent", "qBittorrent.conf"), seed.source
    assert_equal "configs/qbittorrent/qBittorrent.conf", seed.source_display
  end

  def test_rejects_erb_seed_source_at_config_load
    project = @root.join("dotfiles-seed-erb")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      seeds:
        ".config/app/config": "configs/app/config.erb"
      variables: {}
    YAML

    error = assert_raises RuntimeError do
      Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    end
    assert_match(/Seed source must be a plain file, not an ERB template/, error.message)
  end

  def test_validate_seeds_reports_missing_source_and_template_collision
    project = @root.join("dotfiles-seed-validate")
    project.join("configs", "nvim").mkpath
    project.join("configs", "app.conf").write("template\n")
    project.join("configs", "nvim", "init.lua").write("vim.o.number = true\n")
    project.join("configs", "seed.lua").write("seed\n")
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/app/app.conf": "configs/app.conf"
        ".config/nvim": "configs/nvim"
      seeds:
        ".config/app/app.conf": "configs/missing.conf"
        ".config/nvim/lua/app.lua": "configs/seed.lua"
      variables: {}
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    errors = cfg.validate_seeds

    assert_includes errors.join("\n"), ".config/app/app.conf: source file not found"
    assert_includes errors, ".config/app/app.conf: seed target collides with template target"
    assert_includes errors, ".config/nvim/lua/app.lua: seed target collides with template target"
  end

  def test_seed_may_target_ignored_path_inside_directory_template
    project = @root.join("dotfiles-seed-inside-ignore")
    project.join("configs", "herdr").mkpath
    project.join("configs", "herdr", "config.toml").write("managed = true\n")
    project.join("configs", "plugin-state.json").write("{}\n")
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/herdr":
          source: "configs/herdr"
          ignore: "plugins/"
      seeds:
        ".config/herdr/plugins/state.json": "configs/plugin-state.json"
      variables: {}
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    assert_empty cfg.validate_seeds
  end

  def test_theme_variables_override_base_variables
    project = @root.join("dotfiles-theme")
    project.join("configs", "kitty").mkpath
    project.join("configs", "kitty", "kitty.conf.erb").write("font <%= font_size %>")
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write(<<~YAML)
      font_size: 16
      colors:
        bg: "#111111"
        fg: "#eeeeee"
    YAML
    project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates:
        ".config/kitty/kitty.conf": "configs/kitty/kitty.conf.erb"
      variables:
        font_size: 13
        colors:
          bg: "#000000"
          accent: "#ff0000"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    assert_equal 16, cfg.variables.font_size
    assert_equal "#111111", cfg.variables.colors.bg
    assert_equal "#eeeeee", cfg.variables.colors.fg
    assert_equal "#ff0000", cfg.variables.colors.accent
  end

  def test_variable_override_state_has_highest_priority
    project = @root.join("dotfiles-variable-priority")
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write(<<~YAML)
      font_size: 16
    YAML
    project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates: {}
      variables:
        font_size: 13
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 16, cfg.variable_value("font_size")

    cfg.set_variable_override!("font_size", "20")

    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 20, cfg2.variable_value("font_size")
  end

  def test_variable_mappings_are_plain_nested_objects
    project = @root.join("dotfiles-variable-definition")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          default:
            palette:
              bg: "#000000"
          system: true
        leader: " "
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal "#000000", cfg.variable_value("theme.default.palette.bg")
    assert_equal true, cfg.variable_value("theme.system")
    assert_equal " ", cfg.variable_value("leader")
  end

  def test_set_and_get_nested_variable_override
    project = @root.join("dotfiles-variable-nested")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        validates:
          some_variable:
            sub_var1: 1
            sub_var2: 2
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("validates.some_variable.sub_var1", "99")

    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 99, cfg2.variable_value("validates.some_variable.sub_var1")
    assert_equal 2, cfg2.variable_value("validates.some_variable.sub_var2")
  end

  def test_set_variable_override_coerces_scalar_values_by_default_type
    project = @root.join("dotfiles-variable-types")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        count: 1
        ratio: 1.5
        enabled: false
        label: "default"
        flexible:
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("count", "20")
    cfg.set_variable_override!("ratio", "2.75")
    cfg.set_variable_override!("enabled", "true")
    cfg.set_variable_override!("label", "123")
    cfg.set_variable_override!("flexible", "anything")

    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 20, cfg2.variable_value("count")
    assert_in_delta 2.75, cfg2.variable_value("ratio")
    assert_equal true, cfg2.variable_value("enabled")
    assert_equal "123", cfg2.variable_value("label")
    assert_equal "anything", cfg2.variable_value("flexible")
  end

  def test_set_variable_override_rejects_invalid_scalar_values
    project = @root.join("dotfiles-variable-invalid-values")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        count: 1
        enabled: false
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    number_error = assert_raises(RuntimeError) { cfg.set_variable_override!("count", "many") }
    assert_match(/Invalid number for `count`/, number_error.message)

    boolean_error = assert_raises(RuntimeError) { cfg.set_variable_override!("enabled", "yes") }
    assert_match(/expected `true` or `false`/, boolean_error.message)
  end

  def test_set_variable_override_rejects_objects_and_arrays
    project = @root.join("dotfiles-variable-containers")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        palette:
          bg: "#000000"
        workspaces:
          - main
          - chat
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    object_error = assert_raises(RuntimeError) { cfg.set_variable_override!("palette", "value") }
    assert_match(/Cannot set object variable `palette`/, object_error.message)

    array_error = assert_raises(RuntimeError) { cfg.set_variable_override!("workspaces", "value") }
    assert_match(/Cannot set array variable `workspaces`/, array_error.message)
  end

  def test_set_variable_override_rejects_unknown_path
    project = @root.join("dotfiles-variable-unknown")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    error = assert_raises RuntimeError do
      cfg.set_variable_override!("palette.bg", "#000000")
    end
    assert_match(/Unknown variable path `palette\.bg`/, error.message)
  end

  def test_set_variable_override_has_no_reserved_system_variable
    project = @root.join("dotfiles-variable-system")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("theme.palette.bg", "#111111")

    assert_equal "#111111", cfg.variable_value("theme.palette.bg")
  end

  def test_delete_variable_override_has_no_reserved_system_variable
    project = @root.join("dotfiles-variable-system-del")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("theme.palette.bg", "#111111")
    cfg.delete_variable_override!("theme.palette.bg")

    assert_equal "#000000", cfg.variable_value("theme.palette.bg")
  end

  def test_delete_variable_override_restores_effective_value
    project = @root.join("dotfiles-variable-delete")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        validates:
          some_variable:
            sub_var1: 1
            sub_var2: 2
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("validates.some_variable.sub_var1", "99")
    assert_equal 99, cfg.variable_value("validates.some_variable.sub_var1")

    cfg.delete_variable_override!("validates.some_variable.sub_var1")
    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 1, cfg2.variable_value("validates.some_variable.sub_var1")
  end

  def test_variable_values_returns_full_effective_mapping
    project = @root.join("dotfiles-variable-values")
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write(<<~YAML)
      palette:
        bg: "#111111"
        fg: "#eeeeee"
    YAML
    project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates: {}
      variables:
        font_size: 13
        palette:
          bg: "#000000"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    cfg.set_variable_override!("font_size", "20")

    all = cfg.variable_values
    assert_equal 20, all["font_size"]
    assert_equal "#111111", all["palette"]["bg"]
    assert_equal "#eeeeee", all["palette"]["fg"]
  end

  def test_variable_paths_for_completion_include_all_schema_paths
    project = @root.join("dotfiles-variable-paths")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        font_size: 13
        theme:
          palette:
            bg: "#000000"
          system: true
        palette:
          bg: "#ffffff"
        workspaces:
          - main
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    paths = cfg.variable_paths

    assert_includes paths, "theme"
    assert_includes paths, "theme.palette.bg"
    assert_includes paths, "theme.system"
    assert_includes paths, "font_size"
    assert_includes paths, "palette"
    assert_includes paths, "palette.bg"
    assert_includes paths, "workspaces"
  end

  def test_null_schema_accepts_scalar_overrides_but_rejects_containers
    project = @root.join("dotfiles-null-schema")
    project.join("themes", "scalar").mkpath
    project.join("themes", "scalar", "theme.yaml").write("flexible: 42\n")
    project.join("themes", "object").mkpath
    project.join("themes", "object", "theme.yaml").write("flexible:\n  nested: value\n")
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        flexible:
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    assert_empty cfg.validate_theme_overrides("scalar")
    assert_includes cfg.validate_theme_overrides("object"),
                    "Type mismatch for `flexible`: expected scalar, got object"
  end

  def test_validate_theme_overrides_reports_type_mismatch
    project = @root.join("dotfiles-theme-override-validation")
    project.join("themes", "broken").mkpath
    project.join("themes", "broken", "theme.yaml").write(<<~YAML)
      theme:
        palette:
          bg: "#111111"
      font_size: "large"
    YAML
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          palette:
            bg: "#000000"
          system: true
        font_size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    errors = cfg.validate_theme_overrides("broken")
    assert_includes errors, "Type mismatch for `font_size`: expected number, got string"
  end

  def test_theme_from_state_overrides_config_default_theme
    project = @root.join("dotfiles-theme-state")
    project.join("configs").mkpath
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 14\n")
    project.join("themes", "gruvbox").mkpath
    project.join("themes", "gruvbox", "theme.yaml").write("font_size: 17\n")
    project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates: {}
      variables:
        font_size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal "tokyo-night", cfg.current_theme
    assert_equal 14, cfg.variables.font_size

    cfg.set_active_theme!("gruvbox")

    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal "gruvbox", cfg2.current_theme
    assert_equal 17, cfg2.variables.font_size
  end

  def test_missing_theme_in_state_is_ignored
    project = @root.join("dotfiles-missing-theme-in-state")
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 14\n")
    project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates: {}
      variables:
        font_size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    state_file = Pathname.new(cfg.state_path).join("theme")
    state_file.dirname.mkpath
    state_file.write("missing-theme\n")

    cfg2 = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal "tokyo-night", cfg2.current_theme
    assert_equal 14, cfg2.variables.font_size
  end

  def test_theme_can_use_variables_root_key
    project = @root.join("dotfiles-theme-variables-root")
    project.join("configs").mkpath
    project.join("themes", "gruvbox").mkpath
    project.join("themes", "gruvbox", "theme.yaml").write(<<~YAML)
      variables:
        font_size: 15
        theme_name: "gruvbox"
    YAML
    project.join("configen.yaml").write(<<~YAML)
      theme: "gruvbox"
      templates: {}
      variables:
        font_size: 13
        theme_name: "default"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal 15, cfg.variables.font_size
    assert_equal "gruvbox", cfg.variables.theme_name
  end

  def test_directory_string_mapping_resolves_source_path
    project = @root.join("dotfiles2")
    project.join("configs", "nvim").mkpath
    project.join("configs", "nvim", "init.lua").write("vim.o.number = true")
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/nvim": "configs/nvim"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    nvim = cfg.templates.fetch(".config/nvim")

    assert_equal project.join("configs", "nvim"), nvim.source
  end

  def test_loads_hooks_with_changed_and_if_condition
    project = @root.join("dotfiles-hooks")
    project.join("configs").mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      hooks:
        before:
          - description: "pre-transition"
            run: "echo before"
            changed:
              - ".config/niri/**"
            if: "pgrep -x niri >/dev/null"
        after:
          - "echo after"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    assert_equal 1, cfg.hooks[:before].size
    assert_equal "pre-transition", cfg.hooks[:before][0].description
    assert_equal "echo before", cfg.hooks[:before][0].run
    assert_equal [".config/niri/**"], cfg.hooks[:before][0].changed
    assert_equal "pgrep -x niri >/dev/null", cfg.hooks[:before][0].if_command

    assert_equal 1, cfg.hooks[:after].size
    assert_equal "echo after", cfg.hooks[:after][0].description
    assert_equal "echo after", cfg.hooks[:after][0].run
  end

  def test_rejects_exact_option_in_template_spec
    project = @root.join("dotfiles3")
    project.join("configs", "nvim").mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/nvim":
          source: "configs/nvim"
          exact: false
    YAML

    error = assert_raises RuntimeError do
      Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    end
    assert_match(/does not support `exact`/, error.message)
  end

  def test_finds_configen_yaml_in_system_config_directory
    config_path = @system_config_root.join("users", "testuser", "current", "configen.yaml")
    config_path.dirname.mkpath
    config_path.write("templates: {}\n")

    cfg = Configen::Config.new(env: @env, home: @home, system_config_root: @system_config_root)
    assert_equal config_path, cfg.config_path
  end

  def test_prefers_configen_yaml_in_current_directory
    project = @root.join("project")
    project.mkpath
    config_path = project.join("configen.yaml")
    config_path.write("templates: {}\n")
    system_config_path = @system_config_root.join("users", "testuser", "current", "configen.yaml")
    system_config_path.dirname.mkpath
    system_config_path.write("templates: {}\n")

    Dir.chdir(project) do
      cfg = Configen::Config.new(env: @env, home: @home, system_config_root: @system_config_root)
      assert_equal config_path, cfg.config_path
    end
  end

  def test_raises_when_theme_file_is_missing
    project = @root.join("dotfiles-missing-theme")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      theme: "missing"
      templates: {}
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    error = assert_raises RuntimeError do
      cfg.variables
    end
    assert_match(/Theme file not found/, error.message)
  end

  def test_rejects_theme_path_traversal
    project = @root.join("dotfiles-theme-traversal")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      theme: "../outside"
      templates: {}
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    error = assert_raises RuntimeError do
      cfg.variables
    end
    assert_match(/must not include `\.\.`/, error.message)
  end

  def test_available_themes_reads_directories_with_theme_yaml
    project = @root.join("dotfiles-available-themes")
    project.join("themes", "tokyo-night").mkpath
    project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 14\n")
    project.join("themes", "gruvbox").mkpath
    project.join("themes", "gruvbox", "theme.yaml").write("font_size: 13\n")
    project.join("themes", "invalid").mkpath
    project.join("themes", "invalid", "something.yaml").write("x: 1\n")
    project.join("configen.yaml").write("templates: {}\n")

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal %w[gruvbox tokyo-night], cfg.available_themes
  end

  def test_rejects_invalid_hooks_shape
    project = @root.join("dotfiles-invalid-hooks")
    project.mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      hooks:
        before:
          run: "echo nope"
    YAML

    error = assert_raises RuntimeError do
      Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    end

    assert_match(/hooks\.before.*list/, error.message)
  end
end
