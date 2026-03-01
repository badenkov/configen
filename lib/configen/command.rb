# frozen_string_literal: true

class Configen::Command
  def initialize(config)
    @config = config
    @home_path = Pathname.new(Dir.home)
    @generator = Configen::Generator.new(home_path: @home_path)
    @hook_runner = Configen::HookRunner.new
    @templates = config.templates
    @errors = {}
  end

  attr_reader :templates, :errors

  def diff(force: false, theme: nil)
    @errors = {}
    vars = resolve_variables_for(theme)
    return [] if vars.nil?

    plan = @generator.plan(@templates, vars, force:)
    add_template_errors(@generator.errors)
    return [] unless @errors.empty?

    changed_paths = (plan[:create] + plan[:update] + plan[:delete]).uniq
    before_hooks = @hook_runner.planned_hooks(phase: "before", hooks: @config.hooks[:before], changed_paths:)
    after_hooks = @hook_runner.planned_hooks(phase: "after", hooks: @config.hooks[:after], changed_paths:)
    format_plan(plan, before_hooks:, after_hooks:)
  rescue StandardError => e
    add_general_error(e.message)
    []
  end

  def apply(dry_run: false, force: false, theme: nil)
    @errors = {}
    vars = resolve_variables_for(theme)
    return false if vars.nil?

    plan = @generator.plan(@templates, vars, force:)
    add_template_errors(@generator.errors)
    return false unless @errors.empty?
    return true if dry_run

    changed_paths = (plan[:create] + plan[:update] + plan[:delete]).uniq

    before_result = @hook_runner.run(phase: "before", hooks: @config.hooks[:before], changed_paths:)

    applied = @generator.apply_from_plan(dry_run: false)
    after_result = if applied
                     @hook_runner.run(phase: "after", hooks: @config.hooks[:after], changed_paths:)
                   else
                     { errors: [] }
                   end

    add_template_errors(@generator.errors)
    add_hook_errors(before_result[:errors], after_result[:errors])
    applied && @errors.empty?
  rescue StandardError => e
    add_general_error(e.message)
    false
  end

  def validate
    @errors = {}

    template_errors = validate_templates_scope
    @errors["templates"] = template_errors unless template_errors.empty?

    theme_errors = validate_themes_scope
    @errors["themes"] = theme_errors unless theme_errors.empty?

    @errors.empty?
  end

  def validate_selected(theme: nil)
    @errors = {}
    vars = resolve_variables_for(theme)
    return false unless @errors.empty?

    @generator.validate_templates(@templates, vars)
    add_template_errors(@generator.errors)
    @errors.empty?
  rescue StandardError => e
    add_general_error(e.message)
    false
  end

  private

  def resolve_variables_for(theme)
    theme_name = @config.current_theme(theme)
    add_selected_theme_errors(theme_name)

    @config.variables(theme:)
  rescue StandardError => e
    add_theme_error(theme || "current", e.message)
    nil
  end

  def add_selected_theme_errors(theme_name)
    return if theme_name.nil?

    add_theme_error(theme_name, @config.validate_theme_overrides(theme_name))
  end

  def add_template_errors(generator_errors)
    messages = flatten_generator_errors(generator_errors)
    return if messages.empty?

    @errors["templates"] ||= []
    @errors["templates"].concat(messages)
    @errors["templates"].uniq!
  end

  def add_hook_errors(*hook_errors)
    hooks = hook_errors.flatten.compact
    return if hooks.empty?

    @errors["hooks"] ||= []
    @errors["hooks"].concat(hooks)
    @errors["hooks"].uniq!
  end

  def add_theme_error(theme_name, messages)
    list = Array(messages).compact
    return if list.empty?

    @errors["themes"] ||= {}
    @errors["themes"][theme_name] ||= []
    @errors["themes"][theme_name].concat(list)
    @errors["themes"][theme_name].uniq!
  end

  def add_general_error(message)
    @errors["general"] ||= []
    @errors["general"] << message
  end

  def format_plan(plan, before_hooks:, after_hooks:)
    lines = []
    lines.concat(plan[:create].map { |path| "CREATE   #{path}" })
    lines.concat(plan[:update].map { |path| "UPDATE   #{path}" })
    lines.concat(plan[:delete].map { |path| "DELETE   #{path}" })
    lines.concat(plan[:conflict].map { |path| "CONFLICT #{path}" })
    lines.concat(before_hooks.map { |hook| "HOOK BEFORE #{hook.description}: #{hook.run}" })
    lines.concat(after_hooks.map { |hook| "HOOK AFTER  #{hook.description}: #{hook.run}" })
    lines << "NO CHANGES" if lines.empty?
    lines
  end

  def validate_templates_scope
    vars = @config.variables(theme: nil)
    return [] if @generator.validate_templates(@templates, vars)

    flatten_generator_errors(@generator.errors)
  rescue StandardError => e
    [e.message]
  end

  def validate_themes_scope
    collect_theme_names.each_with_object({}) do |theme_name, result|
      errors = @config.validate_theme_overrides(theme_name)
      result[theme_name] = errors unless errors.empty?
    rescue StandardError => e
      result[theme_name] = [e.message]
    end
  end

  def collect_theme_names
    names = @config.available_themes
    configured = @config.settings.theme
    unless configured.nil? || configured.to_s.strip.empty?
      names << configured.to_s.strip
    end
    names.uniq.sort
  end

  def flatten_generator_errors(errors)
    errors.each_with_object([]) do |(path, messages), list|
      Array(messages).each do |message|
        if path == "conflicts" || path == "apply"
          list << message
        else
          list << "#{path}: #{message}"
        end
      end
    end
  end
end
