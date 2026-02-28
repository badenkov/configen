# frozen_string_literal: true

require "test_helper"

class Configen::ConfigTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @env = {
        "XDG_STATE_HOME" => @home.join(".local", "state").to_s
      }
      super
    end
  end

  def test_defaults_without_config
    cfg = Configen::Config.new(env: @env, home: @home)

    assert_nil cfg.config_path
    assert_empty cfg.templates
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

  def test_finds_configen_yaml_in_current_directory
    project = @root.join("project")
    project.mkpath
    config_path = project.join("configen.yaml")
    config_path.write("templates: {}\n")

    Dir.chdir(project) do
      cfg = Configen::Config.new(env: @env, home: @home)
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
end
