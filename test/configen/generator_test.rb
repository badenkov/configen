# frozen_string_literal: true

require "test_helper"

class Configen::GeneratorTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @home = @root.join("home")
      @home.mkpath
      @source = @root.join("configs")
      @source.mkpath
      @generator = Configen::Generator.new(home_path: @home)
      super
    end
  end

  def test_plan_and_apply_creates_rendered_files
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf.erb").write("font_size <%= size %>\n")

    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua.erb").write("vim.g.color = '<%= color %>'\n")
    @source.join("nvim", "lua.lua").write("print('ok')\n")

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf.erb"), exact: false),
      ".config/nvim" => Configen::Config::TemplateSpec.new(source: @source.join("nvim"), exact: false)
    }
    vars = Configen::StrictOpenStruct.new({ "size" => 14, "color" => "tokyo-night" })

    plan = @generator.plan(templates, vars)
    assert_equal [".config/kitty/kitty.conf", ".config/nvim/init.lua", ".config/nvim/lua.lua"], plan[:create]
    assert_empty plan[:update]
    assert_empty plan[:conflict]

    assert @generator.apply(templates, vars)
    assert_equal "font_size 14\n", @home.join(".config/kitty/kitty.conf").read
    assert_equal "vim.g.color = 'tokyo-night'\n", @home.join(".config/nvim/init.lua").read
  end

  def test_plan_marks_updates_and_conflicts
    @source.join("app").mkpath
    @source.join("app", "cfg.erb").write("value=<%= value %>\n")
    @home.join(".config").mkpath
    @home.join(".config", "app").write("not-a-dir")

    templates = {
      ".config/app/cfg" => Configen::Config::TemplateSpec.new(source: @source.join("app", "cfg.erb"), exact: false)
    }
    vars = Configen::StrictOpenStruct.new({ "value" => "x" })

    plan = @generator.plan(templates, vars)
    assert_equal [".config/app/cfg"], plan[:conflict]
    refute @generator.valid?
  end

  def test_exact_mode_deletes_extra_files
    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua").write("set number\n")

    target_dir = @home.join(".config", "nvim")
    target_dir.mkpath
    target_dir.join("init.lua").write("old\n")
    target_dir.join("legacy.lua").write("legacy\n")

    templates = {
      ".config/nvim" => Configen::Config::TemplateSpec.new(source: @source.join("nvim"), exact: true)
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/nvim/init.lua"], plan[:update]
    assert_equal [".config/nvim/legacy.lua"], plan[:delete]

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert @home.join(".config/nvim/init.lua").exist?
    refute @home.join(".config/nvim/legacy.lua").exist?
  end
end
