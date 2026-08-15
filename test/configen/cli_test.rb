# frozen_string_literal: true

require "test_helper"

class Configen::CLITest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @project = @root.join("project")
      @project.mkpath
      super
    end
  end

  def with_home(chdir: nil, &block)
    previous_home = Dir.home
    previous_state = ENV.fetch("XDG_STATE_HOME", nil)
    previous_user = ENV.fetch("USER", nil)
    ENV["HOME"] = @home.to_s
    ENV["XDG_STATE_HOME"] = @home.join(".local", "state").to_s
    ENV["USER"] = "testuser"

    if chdir
      Dir.chdir(chdir, &block)
    else
      block.call
    end
  ensure
    ENV["HOME"] = previous_home
    ENV["XDG_STATE_HOME"] = previous_state
    ENV["USER"] = previous_user
  end

  def test_theme_with_unknown_name_raises_thor_error_without_stacktrace
    @project.join("themes", "gruvbox").mkpath
    @project.join("themes", "gruvbox", "theme.yaml").write("size: 12\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables: {}
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      error = assert_raises(Thor::Error) do
        cli.theme("missing")
      end

      assert_includes error.message, "Theme not found: missing"
      assert_includes error.message, "Available themes: gruvbox"
    end
  end

  def test_get_and_set_variable_commands_support_nested_paths
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        validates:
          some_variable:
            sub_var1: 1
            sub_var2: 2
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      _out, _err = capture_io do
        cli.set("validates.some_variable.sub_var1", "99")
      end
      out, _err = capture_io do
        cli.get("validates.some_variable.sub_var1")
      end

      assert_equal "99\n", out
    end
  end

  def test_set_treats_special_yaml_symbols_as_plain_string
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        leader: " "
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      capture_io { cli.set("leader", "*") }
      out, _err = capture_io { cli.get("leader") }

      assert_equal "*\n", out
    end
  end

  def test_get_without_path_prints_all_effective_variables
    @project.join("themes", "tokyo-night").mkpath
    @project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 15\n")
    @project.join("configen.yaml").write(<<~YAML)
      theme: "tokyo-night"
      templates: {}
      variables:
        font_size: 12
        palette:
          bg: "#000000"
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      out, _err = capture_io do
        cli.get
      end

      assert_includes out, "font_size: 15"
      assert_includes out, "palette:"
      assert_includes out, "bg: \"#000000\""
    end
  end

  def test_del_removes_override_and_falls_back_to_base_value
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        size: 12
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      capture_io { cli.set("size", "20") }
      out, _err = capture_io { cli.del("size") }

      assert_includes out, "Deleted override size"
      assert_includes out, "12"
    end
  end

  def test_pull_dry_run_prints_seed_paths_without_copying
    @project.join("configs").mkpath
    source = @project.join("configs", "app.conf")
    source.write("repo\n")
    @home.join(".config", "app").mkpath
    @home.join(".config", "app", "app.conf").write("home\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      seeds:
        ".config/app/app.conf": "configs/app.conf"
      variables: {}
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], { "dry_run" => true }, {})
      out, _err = capture_io { cli.pull }

      assert_includes out, "PULL     .config/app/app.conf -> configs/app.conf"
      assert_includes out, "Dry run complete"
      assert_equal "repo\n", source.read
    end
  end

  def test_set_does_not_reserve_system_variable
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      capture_io { cli.set("theme.palette.bg", "#111111") }
      out, _err = capture_io { cli.get("theme.palette.bg") }

      assert_equal "#111111\n", out
    end
  end

  def test_del_does_not_reserve_system_variable
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      capture_io { cli.set("theme.palette.bg", "#111111") }
      capture_io { cli.del("theme.palette.bg") }
      out, _err = capture_io { cli.get("theme.palette.bg") }

      assert_equal "#000000\n", out
    end
  end

  def test_completion_bash_prints_script
    @project.join("themes", "tokyo-night").mkpath
    @project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 15\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        font_size: 12
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      out, _err = capture_io { cli.completion("bash") }

      assert_includes out, "_configen_completion()"
      assert_includes out, "complete -F _configen_completion configen"
      assert_includes out, "bash zsh fish"
      assert_includes out, "help version diff apply pull validate get set del theme"
      assert_includes out, "completion-data variables 2>/dev/null"
    end
  end

  def test_completion_zsh_prints_script
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      out, _err = capture_io { cli.completion("zsh") }

      assert_includes out, "#compdef configen"
      assert_includes out, "compdef _configen_completion configen"
    end
  end

  def test_completion_fish_prints_script
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      out, _err = capture_io { cli.completion("fish") }

      assert_includes out, "complete -c configen -f"
      assert_includes out, "__fish_use_subcommand"
      refute_includes out, "--config"
    end
  end

  def test_completion_rejects_unknown_shell
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})
      error = assert_raises(Thor::Error) { cli.completion("tcsh") }
      assert_includes error.message, "Unsupported shell `tcsh`"
    end
  end

  def test_failing_commands_raise_so_the_process_exits_non_zero
    @project.join("configs").mkpath
    @project.join("configs", "app.conf.erb").write("size <%= missing %>\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/app/app.conf": "configs/app.conf.erb"
      variables: {}
    YAML

    with_home(chdir: @project) do
      %i[diff apply validate].each do |command|
        cli = Configen::CLI.new([], {}, {})
        error = nil
        capture_io { error = assert_raises(Thor::Error) { cli.public_send(command) } }

        refute_empty error.message, "#{command} must fail with a message"
      end
    end
  end

  def test_apply_refuses_to_overwrite_unmanaged_file_without_force
    @project.join("configs").mkpath
    @project.join("configs", "app.conf").write("generated\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/app/app.conf": "configs/app.conf"
      variables: {}
    YAML

    with_home(chdir: @project) do
      @home.join(".config", "app").mkpath
      @home.join(".config", "app", "app.conf").write("handwritten\n")

      out, = capture_io do
        assert_raises(Thor::Error) { Configen::CLI.new([], {}, {}).apply }
      end

      assert_includes out, "exists and was not created by configen"
      assert_equal "handwritten\n", @home.join(".config/app/app.conf").read

      forced = Configen::CLI.new([], { "force" => true }, {})
      capture_io { forced.apply }

      assert_equal "generated\n", @home.join(".config/app/app.conf").read
    end
  end

  def test_config_option_selects_the_config_file
    other = @root.join("other")
    other.join("configs").mkpath
    other.join("configs", "app.conf").write("from other\n")
    other.join("configen.yaml").write(<<~YAML)
      templates:
        ".config/app/app.conf": "configs/app.conf"
      variables: {}
    YAML

    with_home(chdir: @root) do
      cli = Configen::CLI.new([], { "config" => other.join("configen.yaml").to_s }, {})
      out, = capture_io { cli.diff }

      assert_includes out, "CREATE   .config/app/app.conf"
    end
  end

  def test_config_option_reports_missing_file
    with_home(chdir: @root) do
      cli = Configen::CLI.new([], { "config" => @root.join("nope.yaml").to_s }, {})
      error = assert_raises(Thor::Error) { cli.diff }

      assert_includes error.message, "Config file not found"
    end
  end

  def test_completion_data_themes_and_variables
    @project.join("themes", "tokyo-night").mkpath
    @project.join("themes", "tokyo-night", "theme.yaml").write("font_size: 15\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        font_size: 12
        theme:
          palette:
            bg: "#000000"
          system: true
    YAML

    with_home(chdir: @project) do
      cli = Configen::CLI.new([], {}, {})

      themes_out, _err = capture_io { cli.completion_data("themes") }
      vars_out, _err = capture_io { cli.completion_data("variables") }

      assert_includes themes_out, "tokyo-night"
      assert_includes vars_out, "theme.palette.bg"
      assert_includes vars_out, "theme.system"
      assert_includes vars_out, "font_size"
    end
  end
end
