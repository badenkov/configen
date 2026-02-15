# frozen_string_literal: true

require "open3"

class Configen::Environment
  def initialize(config)
    @config = config

    output_path = File.join(@config.state_path, "current")
    @generator = Configen::Generator.new(output_path:)

    hooks = config.hooks.group_by do |hook|
      hook["when"] || "after"
    end

    hooks["before"]&.each do |hook|
      @generator.before pattern: hook["pattern"] do
        Open3.capture3("bash", "-c", hook["script"]) if hook["script"]
      end
    end
    hooks["after"]&.each do |hook|
      # puts "Add #{hook["script"]}"
      @generator.after pattern: hook["pattern"] do
        Open3.capture3("bash", "-c", hook["script"]) if hook["script"]

        # puts "status #{status}: #{hook["script"]}"
      end
    end

    @templates = config.templates

    @theme = File.exist?(File.join(@config.state_path, "theme")) && File.read(File.join(@config.state_path, "theme"))
    @theme ||= "default"
  end

  attr_reader :templates

  def themes
    # return [] if @config.themes_path.nil?

    root = Pathname.new(@config.themes_path)
    # root = Pathname.new("/home/badenkov/Projects/dotfiles/themes_ng")
    root.glob("*").select(&:directory?).map do |path|
      path.relative_path_from(root)
    end

    # theme_path = themes_path.join("name")
    # raise "Theme doesn't exist" unless theme_path.directory? && theme_path.join(
    #   "settings.yaml"
    # ).exist?
    #
    # @theme ||= Configen::Variables.new(theme_path)
  end

  def theme
    Configen::Variables.load_from File.join(@config.themes_path, @theme)
    @theme
  end

  def theme=(name)
    theme_path = Pathname.new(@config.themes_path).join(name)
    return unless theme_path.exist?

    @theme = name
  end

  def apply
    theme = Configen::Variables.load_from File.join(@config.themes_path, @theme)

    if (result = @generator.render(@templates, theme.settings))
      File.write(File.join(@config.state_path, "theme"), @theme)
    end

    result
  end

  def errors
    @generator.errors
  end

  def variables
    Configen::Variables.load_from File.join(@config.themes_path, @theme)
  end

  # def theme(_name)
  #   theme_path = themes_path.join("name")
  #   raise "Theme doesn't exist" unless theme_path.directory? && theme_path.join(
  #     "settings.yaml"
  #   ).exist?
  #
  #   @theme ||= Configen::Variables.new(theme_path)
  # end
end
