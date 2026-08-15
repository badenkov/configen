# frozen_string_literal: true

class Configen::Config
  DEFAULTS = {
    templates: {},
    seeds: {},
    variables: {},
    themes_dir: "themes",
    theme: nil,
    hooks: {
      before: [],
      after: []
    }
  }.freeze
  SYSTEM_CONFIG_ROOT = "/etc/configen"

  TemplateSpec = Struct.new(:source, :mode, :ignore, keyword_init: true)
  SeedSpec = Struct.new(:source, :source_display, keyword_init: true)
  HookSpec = Struct.new(:description, :run, :changed, :if_command, keyword_init: true)

  attr_reader :settings, :config_path

  def initialize(env: ENV, home: Dir.home, config: nil, system_config_root: SYSTEM_CONFIG_ROOT)
    @env = env
    @home = home
    @system_config_root = system_config_root
    @config_path = resolve_config_path(config)

    @settings = OpenStruct.new(build_config)
  end

  def templates
    @settings.templates
  end

  def seeds
    @settings.seeds
  end

  def hooks
    @settings.hooks
  end

  def variables(theme: nil)
    Configen::StrictOpenStruct.new(variable_values(theme:))
  end

  def variable_values(theme: nil)
    resolved_variables_hash(theme:)
  end

  def variable_value(path, theme: nil)
    values = variable_values(theme:)
    keys = parse_variable_path(path)
    fetch_nested_value!(values, keys)
  end

  def set_variable_override!(path, raw_value)
    keys = parse_variable_path(path)
    expected = validate_variable_path_exists!(keys)
    overrides = load_variable_overrides
    assign_nested_value!(overrides, keys, coerce_override_value(raw_value, expected, path: keys.join(".")))
    save_variable_overrides(overrides)
  end

  def delete_variable_override!(path)
    keys = parse_variable_path(path)
    validate_variable_path_exists!(keys)
    overrides = load_variable_overrides
    removed = delete_nested_key!(overrides, keys)
    raise "Override not found for `#{keys.join(".")}`" unless removed

    save_variable_overrides(overrides)
  end

  # State lives outside the repository: it is per-machine, not per-config.
  def state_path
    @state_path ||= Pathname.new(@env["XDG_STATE_HOME"] || File.join(@home, ".local", "state"))
                            .join("configen").to_s
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
    theme_name = ensure_theme_exists!(name)

    FileUtils.mkdir_p(theme_state_file.dirname)
    File.write(theme_state_file, "#{theme_name}\n")
    theme_name
  end

  def ensure_theme_exists!(name)
    theme_name = normalize_theme_name(name)
    theme_path = resolve_theme_path(theme_name)
    raise "Theme not found: #{theme_name} (expected #{theme_path})" unless theme_path.file?

    theme_name
  end

  def validate_theme_overrides(theme_name)
    name = normalize_theme_name(theme_name)
    theme_vars = load_theme_variables(name)
    collect_override_validation_errors(@settings.variables || {}, theme_vars)
  end

  def validate_variable_overrides
    collect_override_validation_errors(@settings.variables || {}, load_variable_overrides)
  end

  def validate_seeds
    errors = []
    @settings.seeds.each do |target, spec|
      errors << "#{target}: source file not found: #{spec.source}" unless spec.source.file?
      errors << "#{target}: seed source must not be an ERB template: #{spec.source}" if spec.source.extname == ".erb"
      errors << "#{target}: seed target collides with template target" if seed_template_collision?(target)
    end
    errors
  end

  def variable_paths
    collect_variable_paths(@settings.variables || {})
  end

  private

  def build_config
    config = defaults
    config.merge(load_from_file)
  end

  def defaults
    deep_copy(DEFAULTS)
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
    raw_templates = data["templates"] || {}
    raise "`templates` must be a mapping" unless raw_templates.is_a?(Hash)

    templates = raw_templates.each_with_object({}) do |(target, raw_spec), result|
      spec = normalize_template_spec(raw_spec)
      source_path = Pathname.new(base_dir).join(spec.fetch("source")).expand_path
      result[target.to_s] = TemplateSpec.new(source: source_path, mode: spec["mode"], ignore: spec["ignore"])
    end
    raw_seeds = data["seeds"] || {}
    raise "`seeds` must be a mapping" unless raw_seeds.is_a?(Hash)

    seeds = raw_seeds.each_with_object({}) do |(target, raw_source), result|
      source = normalize_seed_source(raw_source)
      source_path = Pathname.new(base_dir).join(source).expand_path
      result[target.to_s] = SeedSpec.new(source: source_path, source_display: source)
    end
    raw_variables = data["variables"] || {}
    raise "`variables` must be a mapping" unless raw_variables.is_a?(Hash)

    themes_dir = data["themes_dir"] || DEFAULTS[:themes_dir]
    raise "`themes_dir` must be a string" unless themes_dir.is_a?(String)

    {
      templates: templates,
      seeds: seeds,
      variables: deep_copy(raw_variables),
      hooks: normalize_hooks(data["hooks"] || {}),
      themes_dir: themes_dir,
      theme: data["theme"]
    }
  end

  def normalize_template_spec(raw_spec)
    case raw_spec
    when String
      { "source" => raw_spec, "mode" => nil, "ignore" => [] }
    when Hash
      source = raw_spec["source"] || raw_spec[:source]
      raise "Template spec must include `source`" if source.nil?
      if raw_spec.key?("exact") || raw_spec.key?(:exact)
        raise "Template spec does not support `exact`; directory mappings are always exact"
      end

      {
        "source" => source.to_s,
        "mode" => normalize_mode(raw_spec["mode"] || raw_spec[:mode]),
        "ignore" => normalize_ignore_patterns(raw_spec["ignore"] || raw_spec[:ignore])
      }
    else
      raise "Template spec must be a string or mapping, got #{raw_spec.class}"
    end
  end

  def normalize_ignore_patterns(raw_ignore)
    return [] if raw_ignore.nil?

    patterns = raw_ignore.is_a?(Array) ? raw_ignore : [raw_ignore]
    patterns.map do |raw_pattern|
      unless raw_pattern.is_a?(String) && !raw_pattern.strip.empty?
        raise "Template ignore must be a string or list of non-empty strings"
      end

      pattern = raw_pattern.strip.delete_prefix("./")
      if Pathname.new(pattern).absolute? || pattern.split("/").include?("..")
        raise "Template ignore pattern must be relative and must not include `..`: #{raw_pattern}"
      end

      pattern
    end.uniq
  end

  def normalize_mode(raw_mode)
    return nil if raw_mode.nil?
    raise "Template mode must be an octal string" unless raw_mode.is_a?(String)

    mode = raw_mode.strip
    raise "Template mode must be an octal string" unless mode.match?(/\A[0-7]{3,4}\z/)

    mode.to_i(8)
  end

  def normalize_seed_source(raw_source)
    raise "Seed source must be a string path, got #{raw_source.class}" unless raw_source.is_a?(String)
    raise "Seed source cannot be empty" if raw_source.strip.empty?
    raise "Seed source must be a plain file, not an ERB template: #{raw_source}" if File.extname(raw_source) == ".erb"

    raw_source
  end

  def seed_template_collision?(seed_target)
    @settings.templates.any? do |template_target, spec|
      next true if seed_target == template_target
      next false unless spec.source.directory? && seed_target.start_with?("#{template_target}/")

      relative = seed_target.delete_prefix("#{template_target}/")
      !Configen::PathPatterns.match?(relative, spec.ignore || [])
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
    if explicit_path
      path = Pathname.new(explicit_path).expand_path
      raise "Config file not found: #{path}" unless path.file?

      return path
    end

    cwd_candidate = Pathname.new(Dir.pwd).join("configen.yaml")
    return cwd_candidate if cwd_candidate.file?

    system_candidate = system_config_path
    return system_candidate if system_candidate&.file?

    nil
  end

  def system_config_path
    user = current_user_name
    return nil if user.nil? || user.empty?

    Pathname.new(@system_config_root).join("users", user, "current", "configen.yaml")
  end

  def current_user_name
    @env["USER"] || @env["LOGNAME"] || Etc.getpwuid(Process.uid).name
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

  def variables_state_file
    Pathname.new(state_path).join("variables.yaml")
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

  def collect_override_validation_errors(base, override, path = nil, errors = [])
    return errors unless override.is_a?(Hash)

    override.each do |raw_key, value|
      key = raw_key.to_s
      key_path = path.nil? ? key : "#{path}.#{key}"
      base_value = fetch_hash_key(base, key)
      if base_value == :__missing__
        errors << "Unknown override `#{key_path}` (not found in base `variables`)"
        next
      end

      unless value_type_compatible?(base_value, value)
        errors << "Type mismatch for `#{key_path}`: expected #{describe_expected_type(base_value)}, " \
                  "got #{describe_type(value)}"
        next
      end

      next unless value.is_a?(Hash) && base_value.is_a?(Hash)

      collect_override_validation_errors(base_value, value, key_path, errors)
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

  def resolved_variables_hash(theme:)
    base = @settings.variables || {}
    themed = deep_merge_hashes(base, load_theme_variables(resolve_active_theme(theme)))
    deep_merge_hashes(themed, load_variable_overrides)
  end

  def parse_variable_path(path)
    value = path.to_s.strip
    raise "Variable path cannot be empty" if value.empty?

    keys = value.split(".")
    raise "Invalid variable path: #{value}" if keys.any?(&:empty?)

    keys
  end

  def fetch_nested_value!(hash, keys)
    keys.reduce(hash) do |current, key|
      value = fetch_hash_key(current, key)
      raise "Variable not found: #{keys.join(".")}" if value == :__missing__

      value
    end
  end

  def validate_variable_path_exists!(keys)
    fetch_nested_value!(@settings.variables || {}, keys)
  rescue StandardError
    raise "Unknown variable path `#{keys.join(".")}` in base `variables`"
  end

  def assign_nested_value!(hash, keys, value)
    cursor = hash
    keys[0..-2].each do |key|
      current = fetch_hash_key(cursor, key)
      if current == :__missing__
        cursor[key] = {}
        cursor = cursor[key]
        next
      end

      raise "Cannot assign nested value into non-object `#{key}`" unless current.is_a?(Hash)

      cursor = current
    end
    cursor[keys[-1]] = value
  end

  def load_variable_overrides
    return {} unless variables_state_file.file?

    data = YAML.safe_load_file(variables_state_file, permitted_classes: [], aliases: false) || {}
    raise "Variables override root must be a mapping: #{variables_state_file}" unless data.is_a?(Hash)

    data
  rescue Psych::SyntaxError => e
    raise "Variables override parse error in #{variables_state_file}: #{e.message}"
  end

  def save_variable_overrides(overrides)
    FileUtils.mkdir_p(variables_state_file.dirname)
    if overrides.empty?
      File.delete(variables_state_file) if variables_state_file.file?
      return
    end

    File.write(variables_state_file, YAML.dump(overrides))
  end

  def coerce_override_value(raw_value, expected, path:)
    value = raw_value.to_s

    case expected
    when Hash
      raise "Cannot set object variable `#{path}`; set one of its leaf values instead"
    when Array
      raise "Cannot set array variable `#{path}`"
    when Numeric
      parse_number(value, path:)
    when true, false
      parse_boolean(value, path:)
    else
      value
    end
  end

  def parse_number(value, path:)
    Integer(value, 10)
  rescue ArgumentError
    begin
      number = Float(value)
      raise ArgumentError unless number.finite?

      number
    rescue ArgumentError
      raise "Invalid number for `#{path}`: #{value.inspect}"
    end
  end

  def parse_boolean(value, path:)
    return true if value == "true"
    return false if value == "false"

    raise "Invalid boolean for `#{path}`: expected `true` or `false`, got #{value.inspect}"
  end

  def delete_nested_key!(hash, keys)
    cursor = hash
    parents = []

    keys[0..-2].each do |key|
      value = fetch_hash_key(cursor, key)
      return false unless value.is_a?(Hash)

      parents << [cursor, key]
      cursor = value
    end

    leaf_key = keys[-1]
    return false unless cursor.is_a?(Hash) && cursor.key?(leaf_key)

    cursor.delete(leaf_key)
    prune_empty_hash_branches!(parents, cursor)
    true
  end

  def prune_empty_hash_branches!(parents, current)
    return unless current.is_a?(Hash) && current.empty?

    parents.reverse_each do |parent_hash, key|
      parent_hash.delete(key)
      break unless parent_hash.empty?
    end
  end

  def value_type_compatible?(expected, actual)
    if expected.nil?
      scalar_value?(actual)
    elsif expected.is_a?(Numeric)
      actual.is_a?(Numeric)
    elsif [true, false].include?(expected)
      [true, false].include?(actual)
    else
      actual.is_a?(expected.class)
    end
  end

  def scalar_value?(value)
    value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
  end

  def describe_type(value)
    if value.nil?
      "nil"
    elsif value.is_a?(Numeric)
      "number"
    elsif [true, false].include?(value)
      "boolean"
    elsif value.is_a?(Hash)
      "object"
    elsif value.is_a?(Array)
      "array"
    else
      value.class.name.downcase
    end
  end

  def describe_expected_type(value)
    value.nil? ? "scalar" : describe_type(value)
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def collect_variable_paths(value, prefix = nil, result = [])
    return result unless value.is_a?(Hash)

    value.each do |raw_key, child|
      key = raw_key.to_s
      path = prefix.nil? ? key : "#{prefix}.#{key}"
      result << path
      collect_variable_paths(child, path, result) if child.is_a?(Hash)
    end

    result.sort.uniq
  end
end
