# frozen_string_literal: true

class Configen::Config
  DEFAULTS = {
    templates: {},
    variables: {},
    themes_dir: "themes",
    theme: nil,
    hooks: {
      before: [],
      after: []
    },
    state_path: lambda { |env, home|
      Pathname.new(env["XDG_STATE_HOME"] || File.join(home, ".local", "state")).join("configen").to_s
    }
  }.freeze

  TemplateSpec = Struct.new(:source, keyword_init: true)
  HookSpec = Struct.new(:description, :run, :changed, :if_command, keyword_init: true)

  attr_reader :settings, :config_path

  def initialize(env: ENV, home: Dir.home, config: nil)
    @env = env
    @home = home
    @config_path = resolve_config_path(config)

    @settings = OpenStruct.new(build_config)
  end

  def templates
    @settings.templates
  end

  def hooks
    @settings.hooks
  end

  def variables(theme: nil)
    merged = deep_merge_hashes(@settings.variables || {}, load_theme_variables(resolve_active_theme(theme)))
    Configen::StrictOpenStruct.new(merged)
  end

  def state_path
    @settings.state_path.to_s
  end

  def current_theme(override = nil)
    resolve_active_theme(override)
  end

  def available_themes
    root = themes_root
    return [] unless root.directory?

    root.children
        .select(&:directory?)
        .select { |dir| dir.join("theme.yaml").file? }
        .map { |dir| dir.basename.to_s }
        .sort
  end

  def set_active_theme!(name)
    theme_name = normalize_theme_name(name)
    theme_path = resolve_theme_path(theme_name)
    raise "Theme not found: #{theme_name} (expected #{theme_path})" unless theme_path.file?

    FileUtils.mkdir_p(theme_state_file.dirname)
    File.write(theme_state_file, "#{theme_name}\n")
    theme_name
  end

  def validate_theme_overrides(theme_name)
    name = normalize_theme_name(theme_name)
    theme_vars = load_theme_variables(name)
    collect_unknown_override_keys(@settings.variables || {}, theme_vars)
  end

  private

  def build_config
    config = defaults
    config.merge(load_from_file)
  end

  def defaults
    DEFAULTS.transform_values do |v|
      if v.is_a?(Proc)
        v.call(@env, @home)
      elsif v.is_a?(Hash)
        Marshal.load(Marshal.dump(v))
      else
        v
      end
    end
  end

  def load_from_file
    return {} if @config_path.nil?

    data = YAML.safe_load_file(@config_path, permitted_classes: [], aliases: false) || {}
    raise "Config root must be a mapping" unless data.is_a?(Hash)

    normalize_values(data, base_dir: File.dirname(@config_path))
  rescue Psych::SyntaxError => e
    raise "Config parse error in #{@config_path}: #{e.message}"
  end

  def normalize_values(data, base_dir:)
    templates = (data["templates"] || {}).each_with_object({}) do |(target, raw_spec), result|
      spec = normalize_template_spec(raw_spec)
      source_path = Pathname.new(base_dir).join(spec.fetch("source")).expand_path
      result[target.to_s] = TemplateSpec.new(source: source_path)
    end
    base_variables = data["variables"] || {}
    raise "`variables` must be a mapping" unless base_variables.is_a?(Hash)

    themes_dir = data["themes_dir"] || DEFAULTS[:themes_dir]
    raise "`themes_dir` must be a string" unless themes_dir.is_a?(String)

    {
      templates: templates,
      variables: base_variables,
      hooks: normalize_hooks(data["hooks"] || {}),
      themes_dir: themes_dir,
      theme: data["theme"]
    }
  end

  def normalize_template_spec(raw_spec)
    case raw_spec
    when String
      { "source" => raw_spec }
    when Hash
      source = raw_spec["source"] || raw_spec[:source]
      raise "Template spec must include `source`" if source.nil?
      if raw_spec.key?("exact") || raw_spec.key?(:exact)
        raise "Template spec does not support `exact`; directory mappings are always exact"
      end

      { "source" => source.to_s }
    else
      raise "Template spec must be a string or mapping, got #{raw_spec.class}"
    end
  end

  def normalize_hooks(raw_hooks)
    raise "`hooks` must be a mapping" unless raw_hooks.is_a?(Hash)

    {
      before: normalize_hook_list(raw_hooks["before"] || raw_hooks[:before], phase: "before"),
      after: normalize_hook_list(raw_hooks["after"] || raw_hooks[:after], phase: "after")
    }
  end

  def normalize_hook_list(raw_list, phase:)
    return [] if raw_list.nil?

    raise "`hooks.#{phase}` must be a list" unless raw_list.is_a?(Array)

    raw_list.each_with_index.map do |item, index|
      normalize_hook_spec(item, phase: phase, index: index)
    end
  end

  def normalize_hook_spec(raw_spec, phase:, index:)
    case raw_spec
    when String
      HookSpec.new(description: raw_spec, run: raw_spec, changed: nil, if_command: nil)
    when Hash
      run = raw_spec["run"] || raw_spec[:run]
      raise "`hooks.#{phase}[#{index}].run` is required" if run.nil? || run.to_s.strip.empty?

      description = raw_spec["description"] || raw_spec[:description] || raw_spec["name"] || raw_spec[:name] || run

      changed = raw_spec["changed"] || raw_spec[:changed]
      if_command = raw_spec["if"] || raw_spec[:if] || raw_spec["if_command"] || raw_spec[:if_command]

      HookSpec.new(
        description: description.to_s,
        run: run.to_s,
        changed: normalize_changed_globs(changed, phase: phase, index: index),
        if_command: if_command&.to_s
      )
    else
      raise "`hooks.#{phase}[#{index}]` must be a string or mapping"
    end
  end

  def normalize_changed_globs(raw_changed, phase:, index:)
    return nil if raw_changed.nil?

    list = raw_changed.is_a?(Array) ? raw_changed : [raw_changed]
    unless list.all? { |item| item.is_a?(String) && !item.strip.empty? }
      raise "`hooks.#{phase}[#{index}].changed` must be a string or list of strings"
    end

    list
  end

  def resolve_config_path(explicit_path)
    return Pathname.new(explicit_path).expand_path if explicit_path

    cwd_candidate = Pathname.new(Dir.pwd).join("configen.yaml")
    return cwd_candidate if cwd_candidate.file?

    nil
  end

  def resolve_active_theme(theme_override = nil)
    explicit = theme_override.nil? ? nil : normalize_theme_name(theme_override)
    explicit || theme_from_state || normalize_optional_theme_name(@settings.theme)
  end

  def theme_from_state
    return nil unless theme_state_file.file?

    theme_name = normalize_optional_theme_name(File.read(theme_state_file).strip)
    return nil if theme_name.nil?
    return nil unless resolve_theme_path(theme_name).file?

    theme_name
  end

  def load_theme_variables(theme_name)
    return {} if theme_name.nil?

    theme_path = resolve_theme_path(theme_name)
    raise "Theme file not found: #{theme_path}" unless theme_path.file?

    raw_theme = YAML.safe_load_file(theme_path, permitted_classes: [], aliases: false) || {}
    raise "Theme root must be a mapping: #{theme_path}" unless raw_theme.is_a?(Hash)

    if raw_theme.key?("variables")
      raise "Theme `variables` must be a mapping: #{theme_path}" unless raw_theme["variables"].is_a?(Hash)

      raw_theme["variables"]
    else
      raw_theme
    end
  rescue Psych::SyntaxError => e
    raise "Theme parse error in #{theme_path}: #{e.message}"
  end

  def resolve_theme_path(theme_name)
    themes_root.join(theme_name, "theme.yaml").expand_path
  end

  def themes_root
    Pathname.new(config_dir).join(@settings.themes_dir)
  end

  def config_dir
    return File.dirname(@config_path) if @config_path

    Dir.pwd
  end

  def theme_state_file
    Pathname.new(state_path).join("theme")
  end

  def normalize_theme_name(name)
    value = name.to_s.strip
    raise "Theme name cannot be empty" if value.empty?

    validate_theme_name!(value)
    value
  end

  def normalize_optional_theme_name(name)
    return nil if name.nil?

    value = name.to_s.strip
    return nil if value.empty?

    validate_theme_name!(value)
    value
  end

  def validate_theme_name!(name)
    raise "Theme name must be relative, got absolute path: #{name}" if Pathname.new(name).absolute?
    raise "Theme name must not include `..`: #{name}" if name.split("/").include?("..")
  end

  def deep_merge_hashes(base, override)
    return base unless override.is_a?(Hash)

    merged = base.dup
    override.each do |key, value|
      merged[key] = if merged[key].is_a?(Hash) && value.is_a?(Hash)
                      deep_merge_hashes(merged[key], value)
                    else
                      value
                    end
    end
    merged
  end

  def collect_unknown_override_keys(base, override, path = nil, errors = [])
    return errors unless override.is_a?(Hash)

    override.each do |raw_key, value|
      key = raw_key.to_s
      key_path = path.nil? ? key : "#{path}.#{key}"
      base_value = fetch_hash_key(base, key)
      if base_value == :__missing__
        errors << "Unknown override `#{key_path}` (not found in base `variables`)"
        next
      end

      next unless value.is_a?(Hash)
      next unless base_value.is_a?(Hash)

      collect_unknown_override_keys(base_value, value, key_path, errors)
    end

    errors
  end

  def fetch_hash_key(hash, key)
    return :__missing__ unless hash.is_a?(Hash)

    return hash[key] if hash.key?(key)

    sym_key = key.to_sym
    return hash[sym_key] if hash.key?(sym_key)

    :__missing__
  end
end
