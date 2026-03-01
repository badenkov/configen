# frozen_string_literal: true

require "find"
require "digest"

class Configen::Generator
  attr_reader :errors, :last_plan

  def initialize(home_path:, manifest_path: nil)
    @home_path = Pathname.new(home_path)
    @manifest_path = manifest_path.nil? ? nil : Pathname.new(manifest_path)
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
    apply_from_plan(dry_run:)
  end

  def validate_templates(templates, variables = {})
    @errors = {}
    build_desired(templates, variables)
    @errors.empty?
  end

  def apply_from_plan(dry_run: false)
    return false unless valid?
    return true if dry_run

    write_files!
    delete_files!
    prune_empty_directories!
    persist_manifest!
    @errors.empty?
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
      desired: desired,
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
          unless force
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

    collect_manifest_stale_entries(plan, desired)

    %i[create update delete conflict unchanged].each do |kind|
      plan[kind] = plan[kind].uniq.sort
    end
    plan
  end

  def collect_manifest_stale_entries(plan, desired)
    manifest = load_manifest
    return if manifest.empty?

    stale_paths = manifest.keys - desired.keys
    stale_paths.each do |rel|
      path = @home_path.join(rel)
      next unless path.file? || path.symlink?

      recorded_sha = manifest[rel]
      if stale_entry_safe_to_delete?(path, recorded_sha)
        plan[:delete] << rel
      else
        plan[:conflict] << rel
        @errors["conflicts"] ||= []
        @errors["conflicts"] << "#{rel}: stale generated file was modified; refusing to delete"
      end
    end
  end

  def stale_entry_safe_to_delete?(path, recorded_sha)
    return false if recorded_sha.to_s.strip.empty?
    return false unless path.file?

    Digest::SHA256.file(path.to_s).hexdigest == recorded_sha
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

  def strip_template_ext(path)
    exts = %w[.erb]
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

  def prune_empty_directories!
    deleted_dirs = @last_plan[:delete].map do |rel|
      @home_path.join(rel).dirname
    end

    deleted_dirs.uniq.each do |dir|
      prune_directory_upwards!(dir)
    end
  end

  def prune_directory_upwards!(start_dir)
    current = start_dir
    home = @home_path.expand_path.to_s

    while current.to_s.start_with?(home) && current != @home_path
      break unless current.directory?
      break unless Dir.empty?(current)

      Dir.rmdir(current)
      current = current.dirname
    end
  end

  def load_manifest
    return {} if @manifest_path.nil? || !@manifest_path.file?

    raw = YAML.safe_load_file(@manifest_path, permitted_classes: [], aliases: false) || {}
    files = raw["files"]
    return {} unless files.is_a?(Hash)

    files.each_with_object({}) do |(rel, info), manifest|
      next unless rel.is_a?(String) && info.is_a?(Hash)

      sha = info["sha256"]
      manifest[rel] = sha.to_s if sha.is_a?(String)
    end
  rescue Psych::SyntaxError => e
    @errors["state"] ||= []
    @errors["state"] << "Manifest parse error in #{@manifest_path}: #{e.message}"
    {}
  end

  def persist_manifest!
    return if @manifest_path.nil?
    return unless @errors.empty?

    files = @last_plan[:desired].transform_values do |content|
      { "sha256" => Digest::SHA256.hexdigest(content) }
    end

    data = {
      "version" => 1,
      "files" => files
    }

    FileUtils.mkdir_p(@manifest_path.dirname)
    File.write(@manifest_path, YAML.dump(data))
  end
end
