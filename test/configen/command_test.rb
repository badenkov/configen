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

  def test_apply_uses_variable_overrides_from_state
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 10
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    cfg.set_variable_override!("size", "18")

    with_home do
      command = Configen::Command.new(cfg)
      assert command.apply
      assert_equal "font_size 18\n", @home.join(".config/kitty/kitty.conf").read
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
          - description: "before-ok"
            run: "echo before-ok >> #{log_path}"
            changed: ".config/kitty/**"
          - description: "before-skip-by-changed"
            run: "echo before-skip-by-changed >> #{log_path}"
            changed: ".config/niri/**"
          - description: "before-skip-by-if"
            run: "echo before-skip-by-if >> #{log_path}"
            if: "test -f #{missing_flag}"
          - description: "before-fail"
            run: "echo before-fail >> #{log_path}; exit 5"
        after:
          - description: "after-ok"
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
          - description: "before-match"
            run: "echo before"
            changed: ".config/**"
          - description: "before-skip"
            run: "echo skip"
            changed: ".config/niri/**"
        after:
          - description: "after-match"
            run: "echo after"
            if: "test ! -f #{missing_flag}"
          - description: "after-skip-by-if"
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

  def test_diff_reports_template_errors_in_structured_form
    @project.join("configs", "kitty.conf.erb").write("font_size <%= missing_size %>\n")
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
      assert_empty diff
      assert command.errors.key?("templates")
      assert_includes command.errors["templates"].join("\n"), ".config/kitty/kitty.conf:"
    end
  end

  def test_apply_reports_selected_theme_errors_only
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("themes", "broken").mkpath
    @project.join("themes", "broken", "theme.yaml").write("unknown: 1\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
      theme: "broken"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      refute command.apply
      assert command.errors.key?("themes")
      assert command.errors["themes"].key?("broken")
      refute command.errors.key?("templates")
    end
  end

  def test_diff_collects_theme_and_template_errors_together
    @project.join("configs", "kitty.conf.erb").write("font_size <%= missing_size %>\n")
    @project.join("themes", "broken").mkpath
    @project.join("themes", "broken", "theme.yaml").write("unknown: 1\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
      theme: "broken"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)

    with_home do
      command = Configen::Command.new(cfg)
      diff = command.diff
      assert_empty diff
      assert command.errors.key?("themes")
      assert command.errors["themes"].key?("broken")
      assert command.errors.key?("templates")
      assert_includes command.errors["templates"].join("\n"), ".config/kitty/kitty.conf:"
    end
  end

  def test_validate_reports_missing_template_variable
    @project.join("configs", "kitty.conf.erb").write("font_size <%= missing_size %>\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    command = Configen::Command.new(cfg)

    refute command.validate
    assert command.errors.key?("templates")
    joined = command.errors["templates"].join("\n")
    assert_includes joined, ".config/kitty/kitty.conf:"
    assert_includes joined, "Undefined variable `missing_size`"
  end

  def test_validate_reports_unknown_theme_override_variable
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("themes", "broken").mkpath
    @project.join("themes", "broken", "theme.yaml").write(<<~YAML)
      size: 14
      extra:
        value: 1
    YAML
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    command = Configen::Command.new(cfg)

    refute command.validate
    assert command.errors.key?("themes")
    assert command.errors["themes"].key?("broken")
    assert_includes command.errors["themes"]["broken"], "Unknown override `extra` (not found in base `variables`)"
  end

  def test_validate_reports_unknown_variable_override_from_state
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    state_file = Pathname.new(cfg.state_path).join("variables.yaml")
    state_file.dirname.mkpath
    state_file.write(<<~YAML)
      unknown:
        value: 1
    YAML

    command = Configen::Command.new(cfg)
    refute command.validate
    assert command.errors.key?("variables")
    assert_includes command.errors["variables"], "Unknown override `unknown` (not found in base `variables`)"
  end

  def test_validate_checks_all_themes_by_default
    @project.join("configs", "kitty.conf.erb").write("font_size <%= size %>\n")
    @project.join("themes", "ok").mkpath
    @project.join("themes", "ok", "theme.yaml").write("size: 14\n")
    @project.join("themes", "broken").mkpath
    @project.join("themes", "broken", "theme.yaml").write("unknown: 1\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/kitty/kitty.conf": "configs/kitty.conf.erb"
      variables:
        size: 12
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: @project.join("configen.yaml").to_s)
    command = Configen::Command.new(cfg)

    refute command.validate
    assert command.errors.key?("themes")
    assert command.errors["themes"].key?("broken")
    refute command.errors["themes"].key?("ok")
  end
end
