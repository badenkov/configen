# frozen_string_literal: true

require "test_helper"

class Configen::CommandTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @env = {
        "XDG_STATE_HOME" => @home.join(".local", "state").to_s
      }
      @project = @root.join("project")
      @project.mkpath
      @project.join("configs").mkpath
      super
    end
  end

  def with_home
    previous = Dir.home
    ENV["HOME"] = @home.to_s
    yield
  ensure
    ENV["HOME"] = previous
  end

  def test_diff_and_apply
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      diff = command.diff
      assert_includes diff, "CREATE   .config/kitty/kitty.conf"

      assert command.apply
      assert_equal "font_size 12\n", @home.join(".config/kitty/kitty.conf").read
    end
  end

  def test_theme_overrides_variables_in_render
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("themes", "screencast").mkpath
    @project.join("themes", "screencast", "theme.yaml").write("size: 20\n")
    @project.join("configen.yaml").write(<<~YAML)
      theme: "screencast"
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      assert command.apply
      assert_equal "font_size 20\n", @home.join(".config/kitty/kitty.conf").read
    end
  end

  def test_apply_uses_theme_from_state
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("themes", "normal").mkpath
    @project.join("themes", "normal", "theme.yaml").write("size: 12\n")
    @project.join("themes", "screencast").mkpath
    @project.join("themes", "screencast", "theme.yaml").write("size: 20\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 10
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    cfg.set_active_theme!("screencast")

    with_home do
      command = Configen::Command.new(cfg)
      assert command.apply
      assert_equal "font_size 20\n", @home.join(".config/kitty/kitty.conf").read
    end
  end
end
