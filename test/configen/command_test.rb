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

  def test_apply_runs_matching_hooks_and_reports_failures_without_stopping
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    log_path = @root.join("hook.log")
    missing_flag = @root.join("missing.flag")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 14
      hooks:
        before:
          - name: "before-ok"
            run: "echo before-ok >> #{log_path}"
            changed: ".config/kitty/**"
          - name: "before-skip-by-changed"
            run: "echo before-skip-by-changed >> #{log_path}"
            changed: ".config/niri/**"
          - name: "before-skip-by-if"
            run: "echo before-skip-by-if >> #{log_path}"
            if: "test -f #{missing_flag}"
          - name: "before-fail"
            run: "echo before-fail >> #{log_path}; exit 5"
        after:
          - name: "after-ok"
            run: "echo after-ok >> #{log_path}"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      refute command.apply
      assert_equal "font_size 14\n", @home.join(".config/kitty/kitty.conf").read

      lines = File.readlines(log_path, chomp: true)
      assert_equal %w[before-ok before-fail after-ok], lines
      assert command.errors.key?("hooks")
      assert_includes command.errors["hooks"].join("\n"), "[before] before-fail"
    end
  end

  def test_apply_dry_run_does_not_execute_hooks
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    log_path = @root.join("hook-dry.log")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
      hooks:
        before:
          - "echo before >> #{log_path}"
        after:
          - "echo after >> #{log_path}"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      assert command.apply(dry_run: true)
      refute log_path.exist?
    end
  end

  def test_diff_includes_hooks_that_will_run
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    missing_flag = @root.join("missing.flag")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
      hooks:
        before:
          - name: "before-match"
            run: "echo before"
            changed: ".config/**"
          - name: "before-skip"
            run: "echo skip"
            changed: ".config/niri/**"
        after:
          - name: "after-match"
            run: "echo after"
            if: "test ! -f #{missing_flag}"
          - name: "after-skip-by-if"
            run: "echo after-skip"
            if: "test -f #{missing_flag}"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      diff = command.diff.join("\n")
      assert_includes diff, "CREATE   .config/kitty/kitty.conf"
      assert_includes diff, "HOOK BEFORE before-match: echo before"
      assert_includes diff, "HOOK AFTER  after-match: echo after"
      refute_includes diff, "before-skip"
      refute_includes diff, "after-skip-by-if"
    end
  end
end
