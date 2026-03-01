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

  def with_home
    previous_home = Dir.home
    previous_state = ENV.fetch("XDG_STATE_HOME", nil)
    ENV["HOME"] = @home.to_s
    ENV["XDG_STATE_HOME"] = @home.join(".local", "state").to_s
    yield
  ensure
    ENV["HOME"] = previous_home
    ENV["XDG_STATE_HOME"] = previous_state
  end

  def test_theme_with_unknown_name_raises_thor_error_without_stacktrace
    @project.join("themes", "gruvbox").mkpath
    @project.join("themes", "gruvbox", "theme.yaml").write("size: 12\n")
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables: {}
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
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

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      _out, _err = capture_io do
        cli.set("validates.some_variable.sub_var1", "newvalue")
      end
      out, _err = capture_io do
        cli.get("validates.some_variable.sub_var1")
      end

      assert_includes out, "newvalue"
    end
  end

  def test_set_treats_special_yaml_symbols_as_plain_string
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        leader: " "
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
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

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
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

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      capture_io { cli.set("size", "20") }
      out, _err = capture_io { cli.del("size") }

      assert_includes out, "Deleted override size"
      assert_includes out, "12"
    end
  end

  def test_set_rejects_system_variable
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          default:
            palette:
              bg: "#000000"
          system: true
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      error = assert_raises(Thor::Error) { cli.set("theme.palette.bg", "#111111") }
      assert_includes error.message, "Variable `theme` is system and cannot be overridden"
    end
  end

  def test_del_rejects_system_variable
    @project.join("configen.yaml").write(<<~YAML)
      templates: {}
      variables:
        theme:
          default:
            palette:
              bg: "#000000"
          system: true
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      error = assert_raises(Thor::Error) { cli.del("theme.palette.bg") }
      assert_includes error.message, "Variable `theme` is system and cannot be overridden"
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
          default:
            palette:
              bg: "#000000"
          system: true
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      out, _err = capture_io { cli.completion("bash") }

      assert_includes out, "_configen_completion()"
      assert_includes out, "complete -F _configen_completion configen"
      assert_includes out, "bash zsh fish"
      assert_includes out, "help version diff apply validate get set del theme --config -c"
      assert_includes out, "completion-data variables --mode get"
    end
  end

  def test_completion_zsh_prints_script
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      out, _err = capture_io { cli.completion("zsh") }

      assert_includes out, "#compdef configen"
      assert_includes out, "compdef _configen_completion configen"
    end
  end

  def test_completion_fish_prints_script
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      out, _err = capture_io { cli.completion("fish") }

      assert_includes out, "complete -c configen -f"
      assert_includes out, "__fish_use_subcommand"
      assert_includes out, "case '--config=*'"
    end
  end

  def test_completion_rejects_unknown_shell
    @project.join("configen.yaml").write("templates: {}\nvariables: {}\n")

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      error = assert_raises(Thor::Error) { cli.completion("tcsh") }
      assert_includes error.message, "Unsupported shell `tcsh`"
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
          default:
            palette:
              bg: "#000000"
          system: true
    YAML

    with_home do
      cli = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s }, {})
      cli_set = Configen::CLI.new([], { "config" => @project.join("configen.yaml").to_s, "mode" => "set" }, {})

      themes_out, _err = capture_io { cli.completion_data("themes") }
      vars_get_out, _err = capture_io { cli.completion_data("variables") }
      vars_set_out, _err = capture_io { cli_set.completion_data("variables") }

      assert_includes themes_out, "tokyo-night"
      assert_includes vars_get_out, "theme.palette.bg"
      refute_includes vars_set_out, "theme.palette.bg"
      assert_includes vars_set_out, "font_size"
    end
  end
end
