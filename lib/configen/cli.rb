# frozen_string_literal: true

require "shellwords"

class Configen::CLI < Thor
  # class_option :templates_file, type: :string, required: true
  class_option :config, type: :string
  class_option :flake, type: :string

  desc "version", "Version"
  def version
    build_env do |_env, config|
      puts "Version: #{Configen::VERSION}"

      say "\nTemplates", :bold
      config.templates.each do |k, v|
        say "#{k}: #{v}", :green
      end

      say "\nThemes", :bold
      say config.themes_path, :green

      say "\nState", :bold
      say config.state_path, :green

      say "\nHooks", :bold
      hooks = config.hooks.group_by do |hook|
        hook["when"] || "after"
      end
      say "\nBefore:"
      hooks["before"]&.each do |hook|
        say hook["script"]
      end
      say "\nAfter:"
      hooks["after"]&.each do |hook|
        say hook["script"]
      end
    end
  end


  desc "apply", "Apply configs"
  def apply
    build_env do |env|
      if env.apply
        say "Success! Theme #{env.theme}", :green
      else
        env.errors.each do |k, v|
          say k, [:red, :bold]
          v.each do |msg|
            say "  #{msg}", :red
          end
        end
      end
    end
  end

  desc "themes", "Theme"
  def themes
    build_env do |env|
      puts env.themes
    end
  end

  desc "theme", "Theme"
  def theme(name=nil)
    build_env do |env|
      if name.nil?
        puts env.theme
      else
        env.theme = name
        if env.apply
          say "Set theme #{name}", :green
        else
          env.errors.each do |k, v|
            say k, [:red, :bold]
            v.each do |msg|
              say "  #{msg}", :red
            end
          end
        end
      end
    end
  end

  desc "vars", "Show variables"
  def vars
    build_env do |env, conf|
      require "prettyprint"
      pp env.variables.settings
      binding.irb
    end
  end
  
  desc "watch", "Watch"
  def watch
    if options["config"]
      raise Thor::Error, "File #{options["config"]} doesn't exist" unless File.exist?(options["config"])
      @config ||= Configen::Config.new(config: options["config"])
    elsif options["flake"]
      @config ||= Configen::Config.new(flake: options["flake"])
    end

    @config.watch do |config|
      env ||= Configen::Environment.new(@config)
      if env.apply
        say "Success! Theme #{env.theme}", :green
      else
        env.errors.each do |k, v|
          say k, [:red, :bold]
          v.each do |msg|
            say "  #{msg}", :red
          end
        end
      end
    end
  end

  def self.exit_on_failure?
    true
  end

  no_commands do
    def build_env(&block)
      Dir.mktmpdir do |dir| 
        if options["config"] && options["flake"]
         raise Thor::Error, "Only either --config either --flake should be!"
        end

        if options["config"]
          raise Thor::Error, "File #{options["config"]} doesn't exist" unless File.exist?(options["config"])
          @config ||= Configen::Config.new(config: options["config"])
        elsif options["flake"]
          @config ||= Configen::Config.new(flake: options["flake"])
        else
          @config ||= Configen::Config.new
        end

        

        @environment ||= Configen::Environment.new(@config)

        yield @environment, @config
      end
    end
  end
end
