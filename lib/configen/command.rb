# frozen_string_literal: true

class Configen::Command
  def initialize(config)
    @config = config
    @home_path = Pathname.new(Dir.home)
    @generator = Configen::Generator.new(home_path: @home_path)
    @templates = config.templates
  end

  attr_reader :templates

  def diff(force: false, theme: nil)
    plan = @generator.plan(@templates, @config.variables(theme:), force:)
    format_plan(plan)
  end

  def apply(dry_run: false, force: false, theme: nil)
    @generator.apply(@templates, @config.variables(theme:), dry_run:, force:)
  end

  def errors
    @generator.errors
  end

  private

  def format_plan(plan)
    lines = []
    lines.concat(plan[:create].map { |path| "CREATE   #{path}" })
    lines.concat(plan[:update].map { |path| "UPDATE   #{path}" })
    lines.concat(plan[:delete].map { |path| "DELETE   #{path}" })
    lines.concat(plan[:conflict].map { |path| "CONFLICT #{path}" })
    lines << "NO CHANGES" if lines.empty?
    lines
  end
end
