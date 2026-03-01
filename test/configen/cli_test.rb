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
    previous_home = ENV["HOME"]
    previous_state = ENV["XDG_STATE_HOME"]
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
end
