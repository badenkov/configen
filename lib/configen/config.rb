# frozen_string_literal: true

require 'listen'

class Configen::Config
  DEFAULTS = {
    hooks: [],
    templates: {},
    themes_path: nil,
    state_path: ->(env, home) {
      Pathname.new(env["XDG_STATE_HOME"] || File.join(home, ".local", "state")).join("configen").to_s
    },
  }

  attr_reader :settings

  def initialize(env: ENV, home: Dir.home, config: nil, flake: nil, overrides: {})
    @env = env
    @home = home
    @config = config
    @flake = flake
    @overrides = overrides

    @settings = OpenStruct.new(build_config)
  end

  def hooks
    @settings.hooks
  end

  def templates
    @settings.templates
  end

  def themes_path
    @settings.themes_path&.to_s
  end

  def state_path
    @settings.state_path.to_s
  end

  def watch(&block)
    base_dir = nil
    if @flake
      base_dir = File.expand_path(@flake.split('#').first)
    elsif @config
      base_dir = File.expand_path(File.dirname(@config))
    else
      raise "Только для указанного конфига, или флейка"
    end

    puts "Будем слушать #{base_dir}"

    listener = Listen.to(
      base_dir,
      ignore: %r{.devenv}) do |modified, added, removed|
        changed = modified | added | removed
        
        c = changed.select do |path|
          (templates.any? do |k, v|
            v.to_s.start_with?(path)
          end) || path.start_with?(themes_path)
        end

        block.call(self)

        # puts "* #{changed}"

    end

    listener.start
    sleep
  end

  private
    def build_config

      config = defaults
      config = config.merge(load_from_files)
      # config = config.merge(@overrides.transform_keys(&:to_sym))
      config
    end

    def defaults 
      DEFAULTS.transform_values do |v|
        v.is_a?(Proc) ? v.call(@env, @home) : v
      end
    end

    def load_from_files
      return {} if @config.nil? && config_paths.empty?
      
      merged = {}
      
      if @flake
        merged.merge!(load_flake(@flake))
      elsif @config
        merged.merge!(load_file(@config, base_dir: File.dirname(@config)))
      else
        config_paths.each do |path|
          merged.merge!(load_file(path, base_dir: File.dirname(path)))
        end
      end

      merged
    end

    def load_flake(flake)
      Dir.mktmpdir do |dir| 
        require "open3"
        stdout_str, stderr_str, status = Open3.capture3("nix", "build", flake, "--out-link", File.join(dir, "configen.json"))
        raise "Error to load flake" unless status.success?

        config = File.join(dir, "configen.json")
        base_dir = File.expand_path(@flake.split('#').first)

        load_file(config, base_dir: base_dir)
      end
    end

    def load_file(path, base_dir:)
      return {} unless File.file?(path)

      data = JSON.parse(File.read(path))
      normalize_values(data, base_dir:)

    rescue => e
      warn "Config parse error in #{path}: #{e.message}"
    end

    def normalize_values(data, base_dir:)
      norm = data.dup
      Dir.chdir(base_dir) do
        if norm["templates"]
          norm["templates"].transform_values! do |t|
            Pathname.new(t).expand_path 
          end
        end
      
        norm["themes_path"] = Pathname.new(norm["themes_path"]).expand_path if norm["themes_path"]
      end

      norm
    end

    def config_home
      @env["XDG_CONFIG_HOME"] || File.join(@home, ".config")
    end

    def config_dirs
      dirs = @env["XDG_CONFIG_DIRS"]
      dirs ? dirs.split(":") : []
    end

    def config_paths
      dirs = config_dirs.map { |d| File.join(d, "configen", "config.json") }
      dirs + [File.join(config_home, "configen", "config.json")]
    end
end
