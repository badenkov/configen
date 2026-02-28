# frozen_string_literal: true

class Configen::Config
  DEFAULTS = {
    templates: {},
    variables: {},
    state_path: lambda { |env, home|
      Pathname.new(env["XDG_STATE_HOME"] || File.join(home, ".local", "state")).join("configen").to_s
    }
  }.freeze

  TemplateSpec = Struct.new(:source, :exact, keyword_init: true)

  attr_reader :settings

  def initialize(env: ENV, home: Dir.home, config: nil, overrides: {})
    @env = env
    @home = home
    @config_path = resolve_config_path(config)
    @overrides = overrides

    @settings = OpenStruct.new(build_config)
  end

  def templates
    @settings.templates
  end

  def variables
    Configen::StrictOpenStruct.new(@settings.variables || {})
  end

  def state_path
    @settings.state_path.to_s
  end

  def config_path
    @config_path
  end

  private

  def build_config
    config = defaults
    config.merge(load_from_file)
  end

  def defaults
    DEFAULTS.transform_values do |v|
      v.is_a?(Proc) ? v.call(@env, @home) : v
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
      exact = !!spec["exact"]
      result[target.to_s] = TemplateSpec.new(source: source_path, exact:)
    end

    {
      templates:,
      variables: (data["variables"] || {})
    }
  end

  def normalize_template_spec(raw_spec)
    case raw_spec
    when String
      { "source" => raw_spec, "exact" => false }
    when Hash
      source = raw_spec["source"] || raw_spec[:source]
      raise "Template spec must include `source`" if source.nil?

      {
        "source" => source.to_s,
        "exact" => raw_spec["exact"] || raw_spec[:exact] || false
      }
    else
      raise "Template spec must be a string or mapping, got #{raw_spec.class}"
    end
  end

  def resolve_config_path(explicit_path)
    return Pathname.new(explicit_path).expand_path if explicit_path

    cwd_candidate = Pathname.new(Dir.pwd).join("configen.yaml")
    return cwd_candidate if cwd_candidate.file?

    nil
  end
end
