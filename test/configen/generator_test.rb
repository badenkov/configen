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
      @manifest = @root.join("state", "rendered.yaml")
      @generator = Configen::Generator.new(home_path: @home, manifest_path: @manifest)
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
    assert_equal [".config/nvim/init.lua"], plan[:adopt]
    assert_equal [".config/nvim/legacy.lua"], plan[:delete]

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}), force: true)
    assert @home.join(".config/nvim/init.lua").exist?
    refute @home.join(".config/nvim/legacy.lua").exist?
  end

  def test_existing_unmanaged_file_needs_force_and_is_managed_afterwards
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("generated\n")
    @home.join(".config", "kitty").mkpath
    @home.join(".config", "kitty", "kitty.conf").write("handwritten\n")

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }
    vars = Configen::StrictOpenStruct.new({})

    plan = @generator.plan(templates, vars)
    assert_equal [".config/kitty/kitty.conf"], plan[:adopt]
    assert_empty plan[:update]
    refute @generator.valid?
    refute @generator.apply_from_plan
    assert_equal "handwritten\n", @home.join(".config/kitty/kitty.conf").read

    assert @generator.apply(templates, vars, force: true)
    assert_equal "generated\n", @home.join(".config/kitty/kitty.conf").read

    # Once recorded in the manifest the file is ours: no force needed anymore.
    @source.join("kitty", "kitty.conf").write("generated v2\n")
    plan = @generator.plan(templates, vars)
    assert_equal [".config/kitty/kitty.conf"], plan[:update]
    assert @generator.apply_from_plan
    assert_equal "generated v2\n", @home.join(".config/kitty/kitty.conf").read
  end

  def test_existing_unmanaged_file_with_identical_content_is_unchanged
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("same\n")
    @home.join(".config", "kitty").mkpath
    @home.join(".config", "kitty", "kitty.conf").write("same\n")

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/kitty/kitty.conf"], plan[:unchanged]
    assert_empty plan[:adopt]
    assert @generator.apply_from_plan
  end

  def test_directory_ignore_preserves_app_managed_files_and_subdirectories
    source = @source.join("herdr")
    source.join("plugins").mkpath
    source.join("config.toml").write("managed = true\n")
    source.join("plugins", "bundled.json").write("must not be rendered\n")

    target = @home.join(".config", "herdr")
    target.join("plugins").mkpath
    target.join("config.toml").write("managed = false\n")
    target.join("plugins", "runtime.json").write("runtime\n")
    target.join("plugins.json").write("plugins\n")
    target.join("herdr-client.log").write("client log\n")
    target.join("herdr-server.log").write("server log\n")
    target.join("stale.tmp").write("delete me\n")

    templates = {
      ".config/herdr" => Configen::Config::TemplateSpec.new(
        source:,
        ignore: ["plugins/", "plugins.json", "*.log"]
      )
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}), force: true)

    assert_equal [".config/herdr/config.toml"], plan[:adopt]
    assert_equal [".config/herdr/stale.tmp"], plan[:delete]

    assert @generator.apply_from_plan
    assert_equal "managed = true\n", target.join("config.toml").read
    assert_equal "runtime\n", target.join("plugins", "runtime.json").read
    assert_equal "plugins\n", target.join("plugins.json").read
    assert_equal "client log\n", target.join("herdr-client.log").read
    assert_equal "server log\n", target.join("herdr-server.log").read
    refute target.join("plugins", "bundled.json").exist?
    refute target.join("stale.tmp").exist?
  end

  def test_adding_ignore_releases_previously_managed_file_from_manifest
    source = @source.join("herdr-manifest")
    source.mkpath
    source.join("config.toml").write("managed = true\n")
    source.join("plugins.json").write("initial\n")
    target = @home.join(".config", "herdr")

    initial_templates = {
      ".config/herdr" => Configen::Config::TemplateSpec.new(source:, ignore: [])
    }
    assert @generator.apply(initial_templates, Configen::StrictOpenStruct.new({}))

    target.join("plugins.json").write("app changed\n")
    source.join("plugins.json").delete
    ignored_templates = {
      ".config/herdr" => Configen::Config::TemplateSpec.new(source:, ignore: ["plugins.json"])
    }

    plan = @generator.plan(ignored_templates, Configen::StrictOpenStruct.new({}))
    assert_empty plan[:delete]
    assert_empty plan[:conflict]

    assert @generator.apply_from_plan
    assert_equal "app changed\n", target.join("plugins.json").read

    manifest = YAML.safe_load_file(@manifest)
    refute manifest.fetch("files").key?(".config/herdr/plugins.json")
  end

  def test_ignore_is_rejected_for_file_template
    source = @source.join("herdr.toml")
    source.write("managed = true\n")
    templates = {
      ".config/herdr/config.toml" => Configen::Config::TemplateSpec.new(source:, ignore: ["*.log"])
    }

    @generator.plan(templates, Configen::StrictOpenStruct.new({}))

    assert_includes @generator.errors[".config/herdr/config.toml"],
                    "ignore is supported only for directory templates"
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

  def test_symlink_requires_force
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("new\n")
    @home.join(".config", "kitty").mkpath
    File.symlink(@home.join("some-other.conf"), @home.join(".config", "kitty", "kitty.conf"))

    templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/kitty/kitty.conf"], plan[:adopt]
    refute @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert @home.join(".config/kitty/kitty.conf").symlink?
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

  def test_apply_sets_explicit_mode_and_repairs_mode_drift
    @source.join("ssh").mkpath
    @source.join("ssh", "config.erb").write("Host *\n")
    templates = {
      ".ssh/config" => Configen::Config::TemplateSpec.new(source: @source.join("ssh", "config.erb"), mode: 0o600)
    }

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    path = @home.join(".ssh/config")
    assert_equal 0o600, File.stat(path).mode & 0o7777

    File.chmod(0o644, path)
    plan = @generator.plan(templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".ssh/config"], plan[:update]
    assert @generator.apply_from_plan
    assert_equal 0o600, File.stat(path).mode & 0o7777
  end

  def test_default_mode_inherits_source_executable_bit
    source_file = @source.join("theme.sh.erb")
    source_file.write("#!/bin/sh\necho theme\n")
    File.chmod(0o755, source_file)
    templates = {
      ".config/theme.sh" => Configen::Config::TemplateSpec.new(source: source_file)
    }

    assert @generator.apply(templates, Configen::StrictOpenStruct.new({}))
    assert_equal 0o755, File.stat(@home.join(".config/theme.sh")).mode & 0o7777
  end

  def test_template_render_error_blocks_apply
    @source.join("broken").mkpath
    @source.join("broken", "cfg.erb").write("x=<%= fnot_size %>\n")
    templates = {
      ".config/broken/cfg" => Configen::Config::TemplateSpec.new(source: @source.join("broken", "cfg.erb"))
    }

    variables = Configen::StrictOpenStruct.new({ "font_size" => 12 })
    refute @generator.apply(templates, variables)
    assert @generator.errors.key?(".config/broken/cfg")
    assert_includes @generator.errors[".config/broken/cfg"].join("\n"), "Did you mean `font_size`?"
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

  def test_seeds_are_written_only_when_target_is_missing
    @source.join("qbittorrent").mkpath
    @source.join("qbittorrent", "qBittorrent.conf").write("seed\n")
    File.chmod(0o755, @source.join("qbittorrent", "qBittorrent.conf"))
    @home.join(".config", "existing").mkpath
    @home.join(".config", "existing", "app.conf").write("user-owned\n")

    seeds = {
      ".config/qbittorrent/qBittorrent.conf" => Configen::Config::SeedSpec.new(
        source: @source.join("qbittorrent", "qBittorrent.conf"),
        source_display: "qbittorrent/qBittorrent.conf"
      ),
      ".config/existing/app.conf" => Configen::Config::SeedSpec.new(
        source: @source.join("qbittorrent", "qBittorrent.conf"),
        source_display: "qbittorrent/qBittorrent.conf"
      )
    }

    plan = @generator.plan_seeds(seeds)
    assert_equal [".config/qbittorrent/qBittorrent.conf"], plan[:seed]
    assert_equal [".config/existing/app.conf"], plan[:unchanged]

    assert @generator.apply_seeds_from_plan
    assert_equal "seed\n", @home.join(".config/qbittorrent/qBittorrent.conf").read
    assert_equal 0o755, File.stat(@home.join(".config/qbittorrent/qBittorrent.conf")).mode & 0o7777
    assert_equal "user-owned\n", @home.join(".config/existing/app.conf").read
    refute @manifest.exist?
  end

  def test_pull_copies_changed_home_seed_back_to_source
    @source.join("qbittorrent").mkpath
    source_file = @source.join("qbittorrent", "qBittorrent.conf")
    source_file.write("repo\n")
    @home.join(".config", "qbittorrent").mkpath
    @home.join(".config", "qbittorrent", "qBittorrent.conf").write("home\n")

    seeds = {
      ".config/qbittorrent/qBittorrent.conf" => Configen::Config::SeedSpec.new(
        source: source_file,
        source_display: "qbittorrent/qBittorrent.conf"
      )
    }

    plan = @generator.plan_pull(seeds)
    assert_equal [".config/qbittorrent/qBittorrent.conf"], plan[:pull]

    assert @generator.pull_from_plan(dry_run: true)
    assert_equal "repo\n", source_file.read

    assert @generator.pull_from_plan
    assert_equal "home\n", source_file.read
  end

  def test_manifest_deletes_stale_file_when_template_removed
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("font_size 12\n")
    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua").write("set number\n")

    initial_templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf")),
      ".config/nvim/init.lua" => Configen::Config::TemplateSpec.new(source: @source.join("nvim", "init.lua"))
    }
    updated_templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    assert @generator.apply(initial_templates, Configen::StrictOpenStruct.new({}))
    assert @home.join(".config/nvim/init.lua").exist?

    plan = @generator.plan(updated_templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/nvim/init.lua"], plan[:delete]

    assert @generator.apply_from_plan
    refute @home.join(".config/nvim/init.lua").exist?
  end

  def test_manifest_marks_modified_stale_file_as_conflict
    @source.join("kitty").mkpath
    @source.join("kitty", "kitty.conf").write("font_size 12\n")
    @source.join("nvim").mkpath
    @source.join("nvim", "init.lua").write("set number\n")

    initial_templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf")),
      ".config/nvim/init.lua" => Configen::Config::TemplateSpec.new(source: @source.join("nvim", "init.lua"))
    }
    updated_templates = {
      ".config/kitty/kitty.conf" => Configen::Config::TemplateSpec.new(source: @source.join("kitty", "kitty.conf"))
    }

    assert @generator.apply(initial_templates, Configen::StrictOpenStruct.new({}))
    @home.join(".config/nvim/init.lua").write("manual override\n")

    plan = @generator.plan(updated_templates, Configen::StrictOpenStruct.new({}))
    assert_equal [".config/nvim/init.lua"], plan[:conflict]
    assert_includes(
      @generator.errors["conflicts"].join("\n"),
      ".config/nvim/init.lua: stale generated file was modified"
    )
    refute @generator.apply_from_plan
    assert @home.join(".config/nvim/init.lua").exist?
  end
end
