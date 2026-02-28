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
          exact: true
      variables:
        value: "ok"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)

    kitty = cfg.templates.fetch(".config/kitty/kitty.conf")
    nvim = cfg.templates.fetch(".config/nvim")

    assert_equal project.join("configen.yaml"), cfg.config_path
    assert_equal project.join("configs", "kitty", "kitty.conf.erb"), kitty.source
    assert_equal false, kitty.exact
    assert_equal project.join("configs", "nvim"), nvim.source
    assert_equal true, nvim.exact
    assert_equal "ok", cfg.variables.value
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
end
