# frozen_string_literal: true

class Configen::CLI < Thor
  include Configen::CLICompletion

  class_option :config, type: :string, aliases: "-c", desc: "Path to configen.yaml"

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
  method_option :patch, type: :boolean, default: false, aliases: "-p", desc: "Show file contents as a unified diff"
  def diff
    build_env do |command, config|
      lines = command.diff(theme: options["theme"], patch: options["patch"])
      fail_with(command.errors, "diff failed") unless command.errors.empty?

      lines.each { |line| say line }
      say "Theme: #{config.current_theme(options["theme"]) || "(none)"}", :green
    end
  end

  desc "apply", "Apply configs"
  method_option :dry_run, type: :boolean, default: false
  method_option :force, type: :boolean, default: false, desc: "Take ownership of existing files and symlinks"
  method_option :theme, type: :string
  def apply
    build_env do |command, config|
      applied = command.apply(dry_run: options["dry_run"], force: options["force"], theme: options["theme"])
      fail_with(command.errors, "apply failed") unless applied

      say(options["dry_run"] ? "Dry run complete" : "Apply complete", :green)
      say "Theme: #{config.current_theme(options["theme"]) || "(none)"}", :green
    end
  end

  desc "pull", "Copy changed seed files from $HOME back to sources"
  method_option :dry_run, type: :boolean, default: false
  def pull
    build_env do |command, _config|
      lines = command.pull(dry_run: options["dry_run"])
      fail_with(command.errors, "pull failed") unless command.errors.empty?

      lines.each { |line| say line }
      say(options["dry_run"] ? "Dry run complete" : "Pull complete", :green)
    end
  end

  desc "validate", "Validate templates and theme variables"
  def validate
    build_env do |command, _config|
      fail_with(command.errors, "validation failed") unless command.validate

      say "Validation passed", :green
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

  desc "set VARIABLE VALUE", "Set a typed variable override in state"
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
          message = "#{message}. Available themes: #{available.join(", ")}" unless available.empty?
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

      fail_with(command.errors, "theme is not usable") if name && !command.validate_selected(theme: name)
    end
  end

  desc "completion SHELL", "Generate completion script for bash, zsh, or fish"
  def completion(shell)
    script = case shell
             when "bash"
               build_bash_completion_script
             when "zsh"
               build_zsh_completion_script
             when "fish"
               build_fish_completion_script
             else
               raise Thor::Error, "Unsupported shell `#{shell}`. Use one of: bash, zsh, fish"
             end

    puts script
  end

  desc "completion-data KIND", "Print dynamic completion values (internal)", hide: true
  def completion_data(kind)
    build_env do |_command, config|
      data = case kind
             when "themes"
               config.available_themes
             when "variables"
               config.variable_paths
             else
               raise Thor::Error, "Unsupported kind `#{kind}`. Use one of: themes, variables"
             end

      puts data.join("\n")
    end
  end

  ERROR_SCOPES = {
    "templates" => "Templates",
    "variables" => "Variables",
    "seeds" => "Seeds",
    "adopt" => "Existing files",
    "hooks" => "Hooks",
    "general" => "Errors"
  }.freeze

  no_commands do
    def print_errors(errors)
      ERROR_SCOPES.each do |scope, title|
        print_error_group(title, errors[scope])
      end

      (errors["themes"] || {}).each do |theme_name, messages|
        print_error_group("Theme: #{theme_name}", messages)
      end
    end

    def print_error_group(title, messages)
      return if messages.nil? || messages.empty?

      say title, %i[red bold]
      messages.each { |message| say "  #{message}", :red }
    end

    # Every failing command must report a non-zero exit status: the NixOS
    # activation service and any script wrapping configen depend on it.
    def fail_with(errors, message)
      print_errors(errors)
      raise Thor::Error, message
    end

    def build_env
      @config ||= begin
        Configen::Config.new(config: options["config"])
      rescue StandardError => e
        raise Thor::Error, e.message
      end

      unless @config.config_path
        raise Thor::Error,
              "Config file not found. Create ./configen.yaml or set up /etc/configen/users/$USER/current/configen.yaml."
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
