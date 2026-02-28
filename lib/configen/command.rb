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
    plan = @generator.plan(@templates, @config.variables(theme:), force:)
    changed_paths = (plan[:create] + plan[:update] + plan[:delete]).uniq
    before_hooks = @hook_runner.planned_hooks(phase: "before", hooks: @config.hooks[:before], changed_paths:)
    after_hooks = @hook_runner.planned_hooks(phase: "after", hooks: @config.hooks[:after], changed_paths:)
    format_plan(plan, before_hooks:, after_hooks:)
  end

  def apply(dry_run: false, force: false, theme: nil)
    plan = @generator.plan(@templates, @config.variables(theme:), force:)
    return fail_with_generator_errors unless @generator.valid?
    return succeed_with_generator_errors if dry_run

    changed_paths = (plan[:create] + plan[:update] + plan[:delete]).uniq

    before_result = @hook_runner.run(phase: "before", hooks: @config.hooks[:before], changed_paths:)

    applied = @generator.apply_from_plan(dry_run: false)
    after_result = if applied
                     @hook_runner.run(phase: "after", hooks: @config.hooks[:after], changed_paths:)
                   else
                     { errors: [] }
                   end

    @errors = merge_errors(@generator.errors, before_result[:errors], after_result[:errors])
    applied && before_result[:errors].empty? && after_result[:errors].empty?
  end

  private

  def fail_with_generator_errors
    @errors = merge_errors(@generator.errors)
    false
  end

  def succeed_with_generator_errors
    @errors = merge_errors(@generator.errors)
    true
  end

  def merge_errors(generator_errors, *hook_errors)
    merged = generator_errors.transform_values(&:dup)
    hooks = hook_errors.flatten
    merged["hooks"] = hooks unless hooks.empty?
    merged
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
end
