# frozen_string_literal: true

require "test_helper"

class Configen::ConfigTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @fake_root = Pathname.new(dir)
      @fake_root.join("etc", "xdg", "configen").mkpath
      @fake_root.join("home", ".config", "configen").mkpath
      @fake_root.join("home", ".local", "state", "configen").mkpath

      @fake_env = {
        "XDG_CONFIG_DIRS" => @fake_root.join("etc", "xdg").to_s,
        "XDG_CONFIG_HOME" => @fake_root.join("home", ".config").to_s,
        "XDG_STATE_HOME" => @fake_root.join("home", ".local", "state").to_s,
        "HOME" => @fake_root.join("home").to_s
      }
      @fake_home = @fake_root.join("home")
      super
    end
  end

  def test_defaults_without_files
    cfg = Configen::Config.new(env: {}, home: @fake_home)

    assert_equal [], cfg.hooks
    assert_empty cfg.templates
    assert_nil cfg.themes_path
    assert_equal @fake_home.join(".local", "state", "configen").to_s, cfg.state_path.to_s
  end

  def test_loads_system_config
    @fake_root.join("etc", "xdg", "configen", "config.json").write({
      hooks: [
        { pattern: "git/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "git/config" => "/etc/xdg/configen/template.erb"
      },
      themes_path: "/etc/xdg/configen/themes"
    }.to_json)

    cfg = Configen::Config.new(env: @fake_env, home: @fake_home)

    assert_equal [{ "pattern" => "git/*", "script" => "notify-send 'hi'" }], cfg.hooks
    assert_equal({ "git/config" => Pathname.new("/etc/xdg/configen/template.erb") }, cfg.templates)
    assert_equal "/etc/xdg/configen/themes", cfg.themes_path
    assert_equal @fake_home.join(".local", "state", "configen").to_s, cfg.state_path.to_s
  end

  def test_loads_user_config
    @fake_root.join("etc", "xdg", "configen", "config.json").write({
      hooks: [
        { pattern: "git/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "git/config" => "/etc/xdg/configen/template.erb"
      },
      themes_path: "/etc/xdg/configen/themes"
    }.to_json)
    @fake_root.join("home", ".config", "configen", "config.json").write({
      hooks: [
        { pattern: "niri/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "niri/config.kdl" => "/home/.config/configen/templates/template1.erb"
      },
      themes_path: "/home/.config/configen/themes"
    }.to_json)

    cfg = Configen::Config.new(env: @fake_env, home: @fake_home)

    assert_equal [{ "pattern" => "niri/*", "script" => "notify-send 'hi'" }], cfg.hooks

    assert_equal({ "niri/config.kdl" => Pathname.new("/home/.config/configen/templates/template1.erb") }, cfg.templates)
    assert_equal "/home/.config/configen/themes", cfg.themes_path
    assert_equal @fake_home.join(".local", "state", "configen").to_s, cfg.state_path.to_s
  end

  def test_overrides_config_path
    @fake_root.join("etc", "xdg", "configen", "config.json").write({
      hooks: [
        { pattern: "git/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "git/config" => "/etc/xdg/configen/template.erb"
      },
      themes_path: "/etc/xdg/configen/themes"
    }.to_json)

    @fake_root.join("home", ".config", "configen", "config.json").write({
      hooks: [
        { pattern: "niri/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "niri/config.kdl" => "/home/.config/configen/templates/template1.erb"
      },
      themes_path: "/home/.config/configen/themes"
    }.to_json)

    @fake_root.join("home", "dotfiles").mkpath
    @fake_root.join("home", "dotfiles", "configen.json").write({
      hooks: [
        { pattern: "waybar/*", script: "notify-send 'hi'" }
      ],
      templates: {
        "waybar/config.json" => "/home/dotfiles/templates/template1.erb"
      },
      themes_path: "/home/dotfiles/themes"
    }.to_json)

    cfg = Configen::Config.new(env: @fake_env,
                               home: @fake_home,
                               config: @fake_root.join("home", "dotfiles", "configen.json"))

    assert_equal [{ "pattern" => "waybar/*", "script" => "notify-send 'hi'" }], cfg.hooks

    assert_equal({ "waybar/config.json" => Pathname.new("/home/dotfiles/templates/template1.erb") }, cfg.templates)
    assert_equal "/home/dotfiles/themes", cfg.themes_path
    assert_equal @fake_home.join(".local", "state", "configen").to_s, cfg.state_path.to_s
  end
end
