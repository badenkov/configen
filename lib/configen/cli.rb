# frozen_string_literal: true

class Configen::CLI < Thor
  class_option :config, type: :string, aliases: "-c"

  desc "version", "Version"
  def version
    build_env do |_env, config|
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
  def diff
    build_env do |env|
      env.diff.each do |line|
        say line
      end
    end
  end

  desc "apply", "Apply configs"
  method_option :dry_run, type: :boolean, default: false
  method_option :force, type: :boolean, default: false
  def apply
    build_env do |env|
      if env.apply(dry_run: options["dry_run"], force: options["force"])
        say(options["dry_run"] ? "Dry run complete" : "Apply complete", :green)
      else
        env.errors.each do |k, v|
          say k, %i[red bold]
          v.each do |msg|
            say "  #{msg}", :red
          end
        end
      end
    end
  end

  no_commands do
    def build_env
      if options["config"] && !File.file?(options["config"])
        raise Thor::Error, "File #{options["config"]} doesn't exist"
      end

      @config ||= Configen::Config.new(config: options["config"])
      raise Thor::Error, "Config file not found. Pass -c /path/to/configen.yaml or run from a directory containing configen.yaml." unless @config.config_path

      @environment ||= Configen::Environment.new(@config)

      yield @environment, @config
    end
  end
end
