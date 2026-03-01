# frozen_string_literal: true

require "test_helper"

class Configen::ConfigHooksTest < Minitest::Test
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

  def test_hook_description_defaults_to_run_when_missing
    project = @root.join("dotfiles-hooks-default-description")
    project.join("configs").mkpath
    project.join("configen.yaml").write(<<~YAML)
      templates: {}
      hooks:
        before:
          - run: "echo before-only"
    YAML

    cfg = Configen::Config.new(env: @env, home: @home, config: project.join("configen.yaml").to_s)
    assert_equal "echo before-only", cfg.hooks[:before][0].description
  end
end
