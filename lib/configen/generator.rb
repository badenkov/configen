# frozen_string_literal: true

class Configen::Generator
  attr_reader :errors

  def initialize(output_path:)
    @output_path = Pathname.new(output_path)
    @before = []
    @after = []
  end

  def before(options = {}, &block)
    @before << {
      only: Array(options[:only]),
      pattern: options[:pattern] || "*",
      block: block
    }
  end

  def after(options = {}, &block)
    @after << {
      only: Array(options[:only]),
      pattern: options[:pattern] || "*",
      block: block
    }
  end

  def valid?
    @errors.empty?
  end

  def render(templates, variables)
    @errors = {}

    ## Calculate current state
    @previous = {}
    # @output_path.directory?
    if File.directory?(@output_path)
      @previous = @output_path.glob("**/*").select(&:file?).to_h do |path|
        rel = path.relative_path_from(@output_path).to_s
        sha256 = path
                 .then { File.read(_1) }
                 .then { Digest::SHA256.hexdigest(_1) }

        [rel, sha256]
      end
    end

    ## Prepare templates
    prepared_templates = templates.each_with_object({}) do |item, res|
      rel = item[0]
      path = Pathname.new(item[1])
      if path.directory?
        path.glob("**/*").select(&:file?).each do |p|
          r = strip_template_ext(File.join(rel, p.relative_path_from(path).to_s))
          res[r] = p.to_s
        end
      else
        res[rel] = path.to_s
      end
    end

    ## Render
    @current = {}
    @content = {}
    prepared_templates.each do |rel, template|
      result = render_template(template, variables)
      if result[:content].nil?
        @errors[rel] = result[:errors]
      else
        @current[rel] = Digest::SHA256.hexdigest(result[:content])
        @content[rel] = result[:content]
      end
    end

    @to_update = []
    @to_delete = []
    @to_create = []

    all_keys = @previous.keys | @current.keys
    all_keys.each do |k|
      if @previous.key?(k) && @current.key?(k)
        @to_update << k if @previous[k] != @current[k]
      elsif @previous.key?(k)
        @to_delete << k
      else
        @to_create << k
      end
    end

    # require 'prettyprint'
    # pp({
    #   to_create: @to_create,
    #   to_update: @to_update,
    #   to_delete: @to_delete,
    # })

    # puts "Previous"
    # pp @previous
    # puts "Current"
    # pp @current

    return false unless @errors.empty?

    ## Run before write hooks
    @before.each do |hook|
      files = hook[:only].any? ? [] : (@to_create | @to_update | @to_delete)
      files |= @to_create if hook[:only].include?(:created)
      files |= @to_update if hook[:only].include?(:updated)
      files |= @to_delete if hook[:only].include?(:deleted)

      should_trigger = files.any? { |path| File.fnmatch(hook[:pattern], path) }
      hook[:block]&.call if should_trigger
    end
    ## Write result on disk

    FileUtils.mkdir_p(@output_path)
    (@to_create | @to_update).each do |path|
      dst = @output_path.join(path)

      FileUtils.mkdir_p(File.dirname(dst))
      File.write(dst, @content[path])
    end

    @to_delete.each do |path|
      dst = @output_path.join(path)
      FileUtils.rm(dst)
    end

    @output_path.glob("*").select(&:directory?).each do |dir|
      FileUtils.rmdir(dir) if  dir.empty?
    end

    ## Run after write hooks
    @after.each do |hook|
      files = hook[:only].any? ? [] : (@to_create | @to_update | @to_delete)
      files |= @to_create if hook[:only].include?(:created)
      files |= @to_update if hook[:only].include?(:updated)
      files |= @to_delete if hook[:only].include?(:deleted)

      should_trigger = files.any? { |path| File.fnmatch(hook[:pattern], path) }
      hook[:block]&.call if should_trigger
    end

    true
  end

  private

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
end
