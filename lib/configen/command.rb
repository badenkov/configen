# frozen_string_literal: true

class Configen::Command
  def initialize(config)
    @config = config
    @home_path = Pathname.new(Dir.home)
    manifest_path = Pathname.new(config.state_path).join("rendered.yaml")
    @generator = Configen::Generator.new(home_path: @home_path, manifest_path:)
    @hook_runner = Configen::HookRunner.new
    @templates = config.templates
    @seeds = config.seeds
    @errors = {}
  end

  attr_reader :templates, :seeds, :errors

  def get_variable(path = nil, theme: nil)
    return @config.variable_values(theme:) if path.nil?

    @config.variable_value(path, theme:)
  end

  def set_variable(path, raw_value)
    @config.set_variable_override!(path, raw_value)
  end

  def delete_variable(path)
    @config.delete_variable_override!(path)
  end

  def diff(force: false, theme: nil, patch: false)
    plan, seed_plan = prepare(theme:, force:)
    return [] if plan.nil?

    changed_paths = changed_paths_for(plan)
    before_hooks = @hook_runner.planned_hooks(phase: "before", hooks: @config.hooks[:before], changed_paths:)
    after_hooks = @hook_runner.planned_hooks(phase: "after", hooks: @config.hooks[:after], changed_paths:)
    format_plan(plan, seed_plan:, before_hooks:, after_hooks:, patch:)
  rescue StandardError => e
    add_general_error(e.message)
    []
  end

  def apply(dry_run: false, force: false, theme: nil)
    plan, = prepare(theme:, force:)
    return false if plan.nil?

    add_adopt_errors(plan) unless force
    return false unless @errors.empty?
    return true if dry_run

    changed_paths = changed_paths_for(plan)

    before_result = @hook_runner.run(phase: "before", hooks: @config.hooks[:before], changed_paths:)

    applied = @generator.apply_from_plan(dry_run: false)
    add_template_errors(@generator.errors)

    seeds_applied = applied && @generator.apply_seeds_from_plan(dry_run: false)
    add_seed_errors(@generator.errors) if applied && !seeds_applied

    after_result = if applied
                     @hook_runner.run(phase: "after", hooks: @config.hooks[:after], changed_paths:)
                   else
                     { errors: [] }
                   end

    add_hook_errors(before_result[:errors], after_result[:errors])
    applied && seeds_applied && @errors.empty?
  rescue StandardError => e
    add_general_error(e.message)
    false
  end

  def pull(dry_run: false)
    @errors = {}
    seed_validation_errors = @config.validate_seeds
    add_seed_errors(seed_validation_errors)
    return [] unless @errors.empty?

    plan = @generator.plan_pull(@seeds)
    add_seed_errors(@generator.errors)
    return [] unless @errors.empty?

    pulled = @generator.pull_from_plan(dry_run:)
    add_seed_errors(@generator.errors)
    return [] unless pulled && @errors.empty?

    format_pull_plan(plan)
  rescue StandardError => e
    add_general_error(e.message)
    []
  end

  def validate
    @errors = {}

    template_errors = validate_templates_scope
    @errors["templates"] = template_errors unless template_errors.empty?

    variable_errors = @config.validate_variable_overrides
    @errors["variables"] = variable_errors unless variable_errors.empty?

    seed_errors = @config.validate_seeds
    @errors["seeds"] = seed_errors unless seed_errors.empty?

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

  # Renders and plans everything `diff` and `apply` need, collecting errors from
  # every stage. Returns nil instead of a plan when anything failed, so callers
  # only have to check for that.
  def prepare(theme:, force:)
    @errors = {}
    vars = resolve_variables_for(theme)
    return nil if vars.nil?

    plan = @generator.plan(@templates, vars, force:)
    add_template_errors(@generator.errors)

    seed_plan = empty_seed_plan
    seed_validation_errors = @config.validate_seeds
    if seed_validation_errors.empty?
      seed_plan = @generator.plan_seeds(@seeds)
      add_seed_errors(@generator.errors)
    else
      add_seed_errors(seed_validation_errors)
    end

    @errors.empty? ? [plan, seed_plan] : nil
  end

  def changed_paths_for(plan)
    (plan[:create] + plan[:update] + plan[:adopt] + plan[:delete]).uniq
  end

  def add_adopt_errors(plan)
    return if plan[:adopt].empty?

    messages = plan[:adopt].map { |path| "#{path}: exists and was not created by configen" }
    messages << "Run `configen apply --force` to take ownership of these files (their content will be replaced)."
    @errors["adopt"] = messages
  end

  def resolve_variables_for(theme)
    theme_name = @config.current_theme(theme)
    add_selected_theme_errors(theme_name)
    add_variable_errors(@config.validate_variable_overrides)

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

  def add_seed_errors(generator_errors)
    messages = generator_errors.is_a?(Hash) ? flatten_generator_errors(generator_errors) : Array(generator_errors)
    return if messages.empty?

    @errors["seeds"] ||= []
    @errors["seeds"].concat(messages)
    @errors["seeds"].uniq!
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

  def add_variable_errors(messages)
    list = Array(messages).compact
    return if list.empty?

    @errors["variables"] ||= []
    @errors["variables"].concat(list)
    @errors["variables"].uniq!
  end

  def format_plan(plan, seed_plan:, before_hooks:, after_hooks:, patch: false)
    lines = []
    lines.concat(plan[:create].map { |path| "CREATE   #{path}" })
    lines.concat(plan[:update].map { |path| "UPDATE   #{path}#{mode_note(plan, path)}" })
    lines.concat(plan[:adopt].map { |path| "ADOPT    #{path}#{mode_note(plan, path)}" })
    lines.concat(plan[:delete].map { |path| "DELETE   #{path}" })
    lines.concat(seed_plan[:seed].map { |path| "SEED     #{path}" })
    lines.concat(plan[:conflict].map { |path| "CONFLICT #{path}" })
    lines.concat(seed_plan[:conflict].map { |path| "CONFLICT #{path}" })
    lines.concat(before_hooks.map { |hook| "HOOK BEFORE #{hook.description}: #{hook.run}" })
    lines.concat(after_hooks.map { |hook| "HOOK AFTER  #{hook.description}: #{hook.run}" })
    lines << "NO CHANGES" if lines.empty?
    lines.concat(patch_lines(plan, seed_plan)) if patch
    lines
  end

  def mode_note(plan, path)
    change = plan[:modes][path]
    return "" if change.nil?

    format(" (mode %<from>o -> %<to>o)", from: change.first, to: change.last)
  end

  def patch_lines(plan, seed_plan)
    written = (plan[:create] + plan[:update] + plan[:adopt]).sort.map do |path|
      patch_for(path, current_content(path), plan[:desired].fetch(path).content)
    end
    deleted = plan[:delete].map { |path| patch_for(path, current_content(path), "") }
    seeded = seed_plan[:seed].map { |path| patch_for(path, "", seed_plan[:desired].fetch(path).content) }

    body = (written + deleted + seeded).compact
    body.empty? ? [] : [""] + body.flat_map(&:lines).map(&:chomp)
  end

  def patch_for(path, old_content, new_content)
    old_label = old_content.empty? ? File::NULL : "a/#{path}"
    new_label = new_content.empty? ? File::NULL : "b/#{path}"
    diff = Configen::Diff.unified(old_content, new_content, old_label:, new_label:)
    diff.empty? ? nil : diff
  end

  def current_content(path)
    target = @home_path.join(path)
    return "" unless target.file?

    target.read
  end

  def format_pull_plan(plan)
    lines = plan[:pull].map do |path|
      spec = @seeds.fetch(path)
      "PULL     #{path} -> #{spec.source_display}"
    end
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
    names << configured.to_s.strip unless configured.nil? || configured.to_s.strip.empty?
    names.uniq.sort
  end

  def flatten_generator_errors(errors)
    errors.each_with_object([]) do |(path, messages), list|
      Array(messages).each do |message|
        list << if %w[conflicts apply].include?(path)
                  message
                else
                  "#{path}: #{message}"
                end
      end
    end
  end

  def empty_seed_plan
    {
      seed: [],
      conflict: [],
      unchanged: [],
      desired: {}
    }
  end
end
