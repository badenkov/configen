# frozen_string_literal: true

class Configen::CLI < Thor
  class_option :config, type: :string, aliases: "-c"

  desc "version", "Version"
  def version
    build_env do |_command, config|
      puts "Version: #{Configen::VERSION}"

      say "\nConfig", :bold
      say config.config_path || "not found", :green

      say "\nState", :bold
      say config.state_path, :green
    end
  end

  def self.exit_on_failure?
    true
  end

  desc "diff", "Show planned changes in $HOME"
  method_option :theme, type: :string
  def diff
    build_env do |command, config|
      lines = command.diff(theme: options["theme"])
      if command.errors.empty?
        lines.each do |line|
          say line
        end
        say "Theme: #{config.current_theme(options["theme"]) || "(none)"}", :green
      else
        print_errors(command.errors)
      end
    end
  end

  desc "apply", "Apply configs"
  method_option :dry_run, type: :boolean, default: false
  method_option :force, type: :boolean, default: false
  method_option :theme, type: :string
  def apply
    build_env do |command, config|
      if command.apply(dry_run: options["dry_run"], force: options["force"], theme: options["theme"])
        say(options["dry_run"] ? "Dry run complete" : "Apply complete", :green)
        say "Theme: #{config.current_theme(options["theme"]) || "(none)"}", :green
      else
        print_errors(command.errors)
      end
    end
  end

  desc "validate", "Validate templates and theme variables"
  def validate
    build_env do |command, _config|
      if command.validate
        say "Validation passed", :green
      else
        print_errors(command.errors)
      end
    end
  end

  desc "get [VARIABLE]", "Show effective variables or value for a variable path"
  def get(path = nil)
    build_env do |command, _config|
      value = command.get_variable(path)
      say format_variable_value(value), :green
    rescue StandardError => e
      raise Thor::Error, e.message
    end
  end

  desc "set VARIABLE VALUE", "Set string variable override in state"
  def set(path, raw_value)
    build_env do |command, _config|
      command.set_variable(path, raw_value)
      say "Updated #{path}", :green
      say format_variable_value(command.get_variable(path)), :green
    rescue StandardError => e
      raise Thor::Error, e.message
    end
  end

  desc "del VARIABLE", "Delete variable override from state"
  def del(path)
    build_env do |command, _config|
      command.delete_variable(path)
      say "Deleted override #{path}", :green
      say format_variable_value(command.get_variable(path)), :green
    rescue StandardError => e
      raise Thor::Error, e.message
    end
  end

  desc "theme [NAME]", "Show active theme or set active theme"
  def theme(name = nil)
    build_env do |command, config|
      if name
        begin
          config.set_active_theme!(name)
        rescue StandardError => e
          available = config.available_themes
          message = e.message
          unless available.empty?
            message = "#{message}. Available themes: #{available.join(', ')}"
          end
          raise Thor::Error, message
        end
      end
      active = config.current_theme

      say "Active theme: #{active || "(none)"}", :green
      themes = config.available_themes
      if themes.empty?
        say "No themes found", :yellow
      else
        themes.each do |theme_name|
          marker = theme_name == active ? "*" : " "
          say "#{marker} #{theme_name}"
        end
      end

      if name && !command.validate_selected(theme: name)
        print_errors(command.errors)
      end
    end
  end

  no_commands do
    def print_errors(errors)
      if errors["templates"]
        say "Templates", %i[red bold]
        errors["templates"].each do |msg|
          say "  #{msg}", :red
        end
      end

      if errors["variables"]
        say "Variables", %i[red bold]
        errors["variables"].each do |msg|
          say "  #{msg}", :red
        end
      end

      (errors["themes"] || {}).each do |theme_name, messages|
        say "Theme: #{theme_name}", %i[red bold]
        messages.each do |msg|
          say "  #{msg}", :red
        end
      end

      if errors["hooks"]
        say "Hooks", %i[red bold]
        errors["hooks"].each do |msg|
          say "  #{msg}", :red
        end
      end

      if errors["general"]
        say "Errors", %i[red bold]
        errors["general"].each do |msg|
          say "  #{msg}", :red
        end
      end
    end

    def build_env
      if options["config"] && !File.file?(options["config"])
        raise Thor::Error, "File #{options["config"]} doesn't exist"
      end

      @config ||= Configen::Config.new(config: options["config"])
      unless @config.config_path
        raise Thor::Error,
              "Config file not found. Pass -c /path/to/configen.yaml or run from a directory containing configen.yaml."
      end

      @command ||= Configen::Command.new(@config)

      yield @command, @config
    end

    def format_variable_value(value)
      case value
      when Hash, Array
        YAML.dump(value).sub(/\A---\s*\n/, "").strip
      when NilClass
        "null"
      else
        value.to_s
      end
    end
  end
end
