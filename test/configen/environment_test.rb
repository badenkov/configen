# frozen_string_literal: true

require "test_helper"

class Configen::EnvironmentTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @project = @root.join("project")
      @project.mkpath
      @project.join("configs").mkpath
      super
    end
  end

  def with_home
    previous = ENV["HOME"]
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

    cfg = Configen::Config.new(config: @project.join("configen.yaml").to_s)

    with_home do
      env = Configen::Environment.new(cfg)
      diff = env.diff
      assert_includes diff, "CREATE   .config/kitty/kitty.conf"

      assert env.apply
      assert_equal "font_size 12\n", @home.join(".config/kitty/kitty.conf").read
    end
  end
end
