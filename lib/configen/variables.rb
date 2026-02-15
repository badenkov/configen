# frozen_string_literal: true

class Configen::Variables
  attr_reader :settings, :assets, :templates

  def self.load_from(dir)
    root = Pathname.new(dir)
    return unless root.directory?
    return unless root.join("config.toml").exist?

    content = root.join("config.toml").read
    settings = unless content.nil? then
      Tomlib.load(content) 
    else
      {}
    end

    assets_path = root.join("assets")
    assets = assets_path.glob("**/*").select(&:file?).each_with_object({}) do |path, result|
      rel = path.relative_path_from(assets_path).to_s
      result[rel] = path.to_s
    end

    templates_path = root.join("templates")
    templates = templates_path.glob("**/*").select(&:file?).each_with_object({}) do |path, result|
      rel = path.relative_path_from(templates).to_s
      result[rel] = path.to_s
    end

    new(settings:, assets:, templates:)
  rescue Tomlib::ParseError => e
    puts "ParseError: #{root.join("settings.toml").to_s} on #{e.message}"
  end

  def initialize(settings:, assets:, templates:)
    @settings = Configen::StrictOpenStruct.new(settings)
    @assets = assets
    @templates = templates
  end
end

# Configen::Variables = Data.define(:files) do
#   def self.load_variables(dir)
#     root = Pathname.new(dir)
#     return unless root.directory?
#     return unless root.join("settings.yaml").exist?
#
#     files = root.glob("**/*").select(&:file?).each_with_object({}) do |path, result|
#       rel = path.relative_path_from(root).to_s
#       result[rel] = path.to_s
#     end
#
#     settings = YAML.safe_load_file(root.join("settings.yaml"), symbolize_names: true) || {}
#
#     Configen::Variables.new(files:, settings:)
#   end
#
#   def +(other)
#     raise TypeError, "Unsupported" unless other.is_a?(Configen::Variables)
#
#     f = files.merge(other.files) if other.files.any?
#     s = deep_merge(settings, other.settings)
#
#     self.class.new(files: f, settings: s)
#   end
#
#   def s
#     files["settings.toml"].then do |path|
#       nil unless File.exist?(path)
#       File.read(path)
#     end.then do |content|
#       {} if content.nil?
#       Tomlib.load(content) 
#     end
#   rescue Tomlib::ParseError => e
#     puts "ParseError: #{files["settings.toml"]} on #{e.message}"
#
#   end
#
#   private
#
#   def deep_merge(h1, h2)
#     h1.merge(h2) do |_, v1, v2|
#       if v1.is_a?(Hash) && v2.is_a?(Hash)
#         deep_merge(v1, v2)
#       else
#         v2
#       end
#     end
#   end
# end
#
# class Configen::Variables
#   attr_reader :files, :settings
#
#   def initialize(configs_path)
#     @root_path = Pathname.new(configs_path)
#     @files = {}
#     @settings = {}
#
#     load_files!
#     load_settings!
#   end
#
#   def file_content(path)
#     abs_path = @files[path]
#     return unless abs_path.exist?
#
#     @content ||= {}
#     @content[path] ||= File.read(abs_path)
#   end
#
#   def file_path(path)
#     @files[path]
#   end
#
#   def merge!(other_variables)
#     raise TypeError, "Unsupported" unless other.is_a?(Configen::Variables)
#
#     @files.merge!(other_variables.files)
#     @settings = deep_merge(@settings, other_variables.settings)
#   end
# end
