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
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf.erb")),
      ".config/nvim" => Configen::Config::TemplateSpec.new(source: @source.join("nvim"))
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

  def test_dry_run_does_not_modify_filesystem
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf.erb").write("font_size <%= size %>\n")

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf.erb"))
    }
    vars = Configen::StrictOpenStruct.new({ "size" => 14 })

    assert @generator.apply(templates, vars, dry_run: true)
    refute @home.join(".config/kitty/kitty.conf").exist?
  end

  def test_plan_marks_updates_and_conflicts
    @source.join("app").mkpath
    @source.join("app", "cfg.erb").write("value=<%= value %>\n")
    @home.join(".config").mkpath
    @home.join(".config", "app").write("not-a-dir")

    templates = {
      ".config/app/cfg" => Configen::Config::TemplateSpec.new(source: @source.join("app", "cfg.erb"))
    }
    vars = Configen::StrictOpenStruct.new({ "value" => "x" })

    plan = @generator.plan(templates, vars)
    assert_equal [".config/app/cfg"], plan[:conflict]
    refute @generator.valid?
    refute @generator.apply(templates, vars)
  end

  def test_managed_directories_delete_extra_files
    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua").write("set number\n")

    target_dir = @home.join(".config", "nvim")
    target_dir.mkpath
    target_dir.join("init.lua").write("old\n")
    target_dir.join("legacy.lua").write("legacy\n")

    templates = {
      ".config/nvim" => Configen::Config::TemplateSpec.new(source: @source.join("nvim"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/nvim/init.lua"], plan[:update]
    assert_equal [".config/nvim/legacy.lua"], plan[:delete]

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert @home.join(".config/nvim/init.lua").exist?
    refute @home.join(".config/nvim/legacy.lua").exist?
  end

  def test_conflict_when_target_is_directory_but_template_is_file
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf.erb").write("font_size 12\n")
    @home.join(".config", "kitty", "kitty.conf").mkpath

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf.erb"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/kitty/kitty.conf"], plan[:conflict]
    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
  end

  def test_conflict_when_parent_is_file
    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua").write("set number\n")
    @home.join(".config").write("not-a-dir")

    templates = {
      ".config/nvim" => Configen::Config::TemplateSpec.new(source: @source.join("nvim"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/nvim/init.lua"], plan[:conflict]
    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
  end

  def test_symlink_conflict_without_force
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("new\n")
    @home.join(".config", "kitty").mkpath
    File.symlink(@home.join("some-other.conf"), @home.join(".config", "kitty", "kitty.conf"))

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/kitty/kitty.conf"], plan[:conflict]
    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
  end

  def test_symlink_replaced_with_force
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("new\n")
    @home.join(".config", "kitty").mkpath
    File.symlink(@home.join("some-other.conf"), @home.join(".config", "kitty", "kitty.conf"))

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}), force: true)
    path = @home.join(".config/kitty/kitty.conf")
    assert path.file?
    refute path.symlink?
    assert_equal "new\n", path.read
  end

  def test_idempotent_apply
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf.erb").write("font_size <%= size %>\n")
    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf.erb"))
    }
    vars = Configen::StrictOpenStruct.new({ "size" => 12 })

    assert @generator.apply(templates, vars)
    plan = @generator.plan(templates, vars)
    assert_empty plan[:create]
    assert_empty plan[:update]
    assert_empty plan[:delete]
    assert_empty plan[:conflict]
    assert_equal [".config/kitty/kitty.conf"], plan[:unchanged]
  end

  def test_template_render_error_blocks_apply
    @source.join("broken").mkpath
    @source.join("broken", "cfg.erb").write("x=<%= missing.value %>\n")
    templates = {
      ".config/broken/cfg" => Configen::Config::TemplateSpec.new(source: @source.join("broken", "cfg.erb"))
    }

    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert @generator.errors.key?(".config/broken/cfg")
    refute @home.join(".config/broken/cfg").exist?
  end

  def test_missing_source_blocks_apply
    templates = {
      ".config/app/cfg" => Configen::Config::TemplateSpec.new(source: @source.join("app", "missing.erb"))
    }

    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert @generator.errors.key?(".config/app/cfg")
    refute @home.join(".config/app/cfg").exist?
  end
end
