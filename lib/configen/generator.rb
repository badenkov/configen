# frozen_string_literal: true

require "find"

class Configen::Generator
  attr_reader :errors, :last_plan

  def initialize(home_path:)
    @home_path = Pathname.new(home_path)
    @errors = {}
    @last_plan = {
      create: [],
      update: [],
      delete: [],
      conflict: [],
      unchanged: []
    }
  end

  def valid?
    @errors.empty? && @last_plan[:conflict].empty?
  end

  def plan(templates, variables = {}, force: false)
    @errors = {}

    desired, managed_dir_roots = build_desired(templates, variables)
    @last_plan = build_plan(desired, managed_dir_roots, force:)
  end

  def apply(templates, variables = {}, dry_run: false, force: false)
    plan(templates, variables, force:)
    return false unless valid?
    return true if dry_run

    write_files!
    delete_files!
    true
  end

  private

  def build_desired(templates, variables)
    desired = {}
    managed_dir_roots = []

    templates.each do |target_rel, spec|
      source = spec.source

      if source.directory?
        managed_dir_roots << target_rel
        source.glob("**/*", File::FNM_DOTMATCH).select(&:file?).each do |src|
          rel = src.relative_path_from(source).to_s
          dst = File.join(target_rel, strip_template_ext(rel))
          render_into_desired!(desired, dst, src.to_s, variables)
        end
      else
        render_into_desired!(desired, target_rel, source.to_s, variables)
      end
    end

    [desired, managed_dir_roots]
  end

  def render_into_desired!(desired, target_rel, source_path, variables)
    result = render_template(source_path, variables)
    if result[:content].nil?
      @errors[target_rel] ||= []
      @errors[target_rel].concat(result[:errors])
      return
    end

    desired[target_rel] = result[:content]
  end

  def build_plan(desired, managed_dir_roots, force:)
    plan = {
      desired:,
      create: [],
      update: [],
      delete: [],
      conflict: [],
      unchanged: []
    }

    desired.each do |rel, content|
      dst = @home_path.join(rel)
      if ancestor_is_file?(dst)
        plan[:conflict] << rel
        @errors["conflicts"] ||= []
        @errors["conflicts"] << "#{rel}: parent path is a file"
        next
      end

      if File.directory?(dst)
        plan[:conflict] << rel
        @errors["conflicts"] ||= []
        @errors["conflicts"] << "#{rel}: target is a directory"
        next
      end

      if File.exist?(dst) || File.symlink?(dst)
        if File.symlink?(dst)
          if !force
            plan[:conflict] << rel
            @errors["conflicts"] ||= []
            @errors["conflicts"] << "#{rel}: target is a symlink (use --force to replace)"
            next
          end

          if File.exist?(dst)
            current = File.read(dst)
            if current == content
              plan[:unchanged] << rel
            else
              plan[:update] << rel
            end
          else
            plan[:update] << rel
          end
        elsif File.file?(dst)
          current = File.read(dst)
          if current == content
            plan[:unchanged] << rel
          else
            plan[:update] << rel
          end
        else
          plan[:conflict] << rel
          @errors["conflicts"] ||= []
          @errors["conflicts"] << "#{rel}: target exists and is not a regular file"
        end
      else
        plan[:create] << rel
      end
    end

    managed_dir_roots.each do |root_rel|
      root_abs = @home_path.join(root_rel)
      next unless root_abs.directory?

      Find.find(root_abs.to_s) do |path|
        next if File.directory?(path)

        rel = Pathname.new(path).relative_path_from(@home_path).to_s
        next if desired.key?(rel)

        plan[:delete] << rel
      end
    end

    %i[create update delete conflict unchanged].each do |kind|
      plan[kind] = plan[kind].uniq.sort
    end
    plan
  end

  def render_template(path, variables = {})
    result = {
      errors: [],
      content: nil
    }

    unless File.exist?(path)
      result[:errors] << "file #{path} doesn't exist"
      return result
    end

    case File.extname(path)
    when ".erb"
      render_erb(path, variables)
    # when ".liquid"
    #   render_liquid(path, variables)
    else
      { content: File.read(path) }
    end
  end

  def render_erb(path, variables)
    result = {
      errors: [],
      content: nil
    }

    content = File.read(path)
    template = Configen::ERB::Template.new(content)
    result[:content] = template.render(variables)

    result
  rescue StandardError => e
    result[:errors] << e.message
    result
  rescue SyntaxError
    result[:errors] << "Syntax error"
    result
  end

  def render_liquid(path, _variables)
    File.read(path)
    # content = File.read(path)
    # template = Liquid::Template.parse(content)
    # template.render(variables)
  end

  def strip_template_ext(path)
    exts = %w[.erb .liquid]
    path = Pathname(path)

    ext = path.extname
    if exts.include?(ext)
      (path.dirname + path.basename(ext)).to_s
    else
      path.to_s
    end
  end

  def ancestor_is_file?(path)
    relative = path.relative_path_from(@home_path).to_s
    segments = relative.split("/")
    return false if segments.length <= 1

    current = @home_path
    segments[0...-1].each do |part|
      current = current.join(part)
      return true if current.file? || current.symlink?
    end

    false
  end

  def write_files!
    (@last_plan[:create] | @last_plan[:update]).each do |rel|
      dst = @home_path.join(rel)

      if File.symlink?(dst)
        FileUtils.rm_f(dst)
      elsif File.exist?(dst) && !File.file?(dst)
        @errors["apply"] ||= []
        @errors["apply"] << "#{rel}: cannot overwrite non-file target"
        next
      end

      FileUtils.mkdir_p(dst.dirname)
      File.write(dst, @last_plan[:desired][rel])
    end
  end

  def delete_files!
    @last_plan[:delete].each do |rel|
      dst = @home_path.join(rel)
      FileUtils.rm_f(dst)
    end
  end
end
