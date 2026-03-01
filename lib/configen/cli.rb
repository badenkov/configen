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

      print_errors(command.errors) if name && !command.validate_selected(theme: name)
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
  method_option :mode, type: :string
  def completion_data(kind)
    build_env do |_command, config|
      data = case kind
             when "themes"
               config.available_themes
             when "variables"
               mode = (options["mode"] || "get").to_sym
               raise Thor::Error, "Unsupported mode `#{mode}`. Use one of: get, set, del" unless %i[get set
                                                                                                    del].include?(mode)

               config.variable_paths(mode:)
             else
               raise Thor::Error, "Unsupported kind `#{kind}`. Use one of: themes, variables"
             end

      puts data.join("\n")
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

      return unless errors["general"]

      say "Errors", %i[red bold]
      errors["general"].each do |msg|
        say "  #{msg}", :red
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

    def completion_command_names
      hidden = %w[completion completion-data completion_data]
      self.class.all_commands.keys.reject { |name| hidden.include?(name) }
    end

    def completion_global_options
      completion_options_to_switches(self.class.class_options)
    end

    def completion_command_options
      self.class.all_commands.transform_values do |command|
        completion_options_to_switches(command.options)
      end
    end

    def completion_options_to_switches(options)
      options.each_with_object([]) do |(name, option), memo|
        memo << "--#{name.to_s.tr("_", "-")}"
        memo.concat(option.aliases)
      end.uniq
    end

    def shell_words(words)
      words.join(" ")
    end

    def single_quoted(word)
      "'#{word.gsub("'", "'\\''")}'"
    end

    def zsh_array(words)
      words.map { |word| single_quoted(word) }.join(" ")
    end

    def build_bash_completion_script
      commands = completion_command_names
      global_options = completion_global_options
      command_options = completion_command_options
      case_entries = commands.map do |command_name|
        options = (command_options.fetch(command_name, []) + global_options).uniq
        <<~BASH
          #{command_name})
            COMPREPLY=( $(compgen -W "#{shell_words(options)}" -- "$cur") )
            return
            ;;
        BASH
      end.join

      <<~BASH
        _configen_completion_config_value() {
          local i=1
          local value=""
          while [[ $i -lt $COMP_CWORD ]]; do
            case "${COMP_WORDS[$i]}" in
              -c|--config)
                if [[ $((i + 1)) -lt ${#COMP_WORDS[@]} ]]; then
                  value="${COMP_WORDS[$((i + 1))]}"
                fi
                i=$((i + 2))
                continue
                ;;
              --config=*)
                value="${COMP_WORDS[$i]#--config=}"
                ;;
            esac
            i=$((i + 1))
          done
          printf '%s' "$value"
        }

        _configen_completion_positional_index() {
          local cmd_index="$1"
          local index=0
          local expect_value=0
          local i
          for ((i = cmd_index + 1; i < COMP_CWORD; i++)); do
            local word="${COMP_WORDS[$i]}"
            if [[ $expect_value -eq 1 ]]; then
              expect_value=0
              continue
            fi
            case "$word" in
              -c|--config|--theme)
                expect_value=1
                continue
                ;;
              --config=*|--theme=*)
                continue
                ;;
            esac
            if [[ "$word" != -* ]]; then
              index=$((index + 1))
            fi
          done
          printf '%s' "$index"
        }

        _configen_completion() {
          local cur cmd cmd_index
          cur="${COMP_WORDS[COMP_CWORD]}"
          cmd=""
          cmd_index=0

          local i
          for ((i = 1; i < ${#COMP_WORDS[@]}; i++)); do
            local word="${COMP_WORDS[$i]}"
            if [[ "$word" != -* ]]; then
              cmd="$word"
              cmd_index="$i"
              break
            fi
          done

          if [[ -z "$cmd" ]]; then
            COMPREPLY=( $(compgen -W "#{shell_words(commands + global_options)}" -- "$cur") )
            return
          fi

          local config_value
          config_value="$(_configen_completion_config_value)"
          local -a config_args
          if [[ -n "$config_value" ]]; then
            config_args=(--config "$config_value")
          else
            config_args=()
          fi

          if [[ "$cmd" == "theme" && "$cur" != -* ]]; then
            local themes
            themes="$(configen "${config_args[@]}" completion-data themes 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$themes #{shell_words(global_options)}" -- "$cur") )
            return
          fi

          if [[ "$cmd" == "completion" ]]; then
            COMPREPLY=( $(compgen -W "bash zsh fish #{shell_words(global_options)}" -- "$cur") )
            return
          fi

          if [[ "$cur" != -* ]]; then
            local positional_index
            positional_index="$(_configen_completion_positional_index "$cmd_index")"
            case "$cmd" in
              get)
                if [[ "$positional_index" == "0" ]]; then
                  local vars
                  vars="$(configen "${config_args[@]}" completion-data variables --mode get 2>/dev/null)"
                  COMPREPLY=( $(compgen -W "$vars #{shell_words(global_options)}" -- "$cur") )
                  return
                fi
                ;;
              set)
                if [[ "$positional_index" == "0" ]]; then
                  local vars
                  vars="$(configen "${config_args[@]}" completion-data variables --mode set 2>/dev/null)"
                  COMPREPLY=( $(compgen -W "$vars #{shell_words(global_options)}" -- "$cur") )
                  return
                fi
                ;;
              del)
                if [[ "$positional_index" == "0" ]]; then
                  local vars
                  vars="$(configen "${config_args[@]}" completion-data variables --mode del 2>/dev/null)"
                  COMPREPLY=( $(compgen -W "$vars #{shell_words(global_options)}" -- "$cur") )
                  return
                fi
                ;;
            esac
          fi

          case "$cmd" in
        #{case_entries}    esac
        }

        complete -F _configen_completion configen
      BASH
    end

    def build_zsh_completion_script
      commands = completion_command_names
      global_options = completion_global_options
      command_options = completion_command_options
      case_entries = commands.map do |command_name|
        options = (command_options.fetch(command_name, []) + global_options).uniq
        <<~ZSH
          #{command_name})
            _values 'options' #{zsh_array(options)}
            ;;
        ZSH
      end.join

      <<~ZSH
        #compdef configen

        _configen_completion_config_value() {
          local value=""
          local i
          for ((i = 1; i < CURRENT; i++)); do
            case "${words[i]}" in
              -c|--config)
                if (( i + 1 <= ${#words} )); then
                  value="${words[i + 1]}"
                fi
                i=$((i + 1))
                ;;
              --config=*)
                value="${words[i]#--config=}"
                ;;
            esac
          done
          print -r -- "$value"
        }

        _configen_completion_positional_index() {
          local cmd_index="$1"
          local index=0
          local expect_value=0
          local i
          for ((i = cmd_index + 1; i < CURRENT; i++)); do
            local word="${words[i]}"
            if (( expect_value )); then
              expect_value=0
              continue
            fi
            case "$word" in
              -c|--config|--theme)
                expect_value=1
                continue
                ;;
              --config=*|--theme=*)
                continue
                ;;
            esac
            if [[ "$word" != -* ]]; then
              index=$((index + 1))
            fi
          done
          print -r -- "$index"
        }

        _configen_completion() {
          local context state line
          local -a commands global_options themes vars
          commands=(#{zsh_array(commands)})
          global_options=(#{zsh_array(global_options)})

          _arguments -C \
            '1:command:->command' \
            '*::arg:->args'

          case $state in
            command)
              _describe 'commands' commands
              ;;
            args)
              local cmd=''
              local cmd_index=0
              local i
              for ((i = 2; i <= ${#words}; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                  cmd="${words[i]}"
                  cmd_index=$i
                  break
                fi
              done

              if [[ -z "$cmd" ]]; then
                _values 'items' ${commands[@]} ${global_options[@]}
                return
              fi

              local config_value
              config_value="$(_configen_completion_config_value)"
              local -a config_args
              if [[ -n "$config_value" ]]; then
                config_args=(--config "$config_value")
              else
                config_args=()
              fi

              if [[ "$cmd" == "theme" && CURRENT -eq 3 ]]; then
                themes=(${(f)"$(configen ${config_args[@]} completion-data themes 2>/dev/null)"})
                _describe 'themes' themes
                return
              fi

              if [[ "$cmd" == "completion" ]]; then
                _values 'shells' 'bash' 'zsh' 'fish' ${global_options[@]}
                return
              fi

              if [[ "${words[CURRENT]}" != -* ]]; then
                local positional_index
                positional_index="$(_configen_completion_positional_index "$cmd_index")"
                case "$cmd" in
                  get)
                    if [[ "$positional_index" == "0" ]]; then
                      vars=(${(f)"$(configen ${config_args[@]} completion-data variables --mode get 2>/dev/null)"})
                      _describe 'variables' vars
                      return
                    fi
                    ;;
                  set)
                    if [[ "$positional_index" == "0" ]]; then
                      vars=(${(f)"$(configen ${config_args[@]} completion-data variables --mode set 2>/dev/null)"})
                      _describe 'variables' vars
                      return
                    fi
                    ;;
                  del)
                    if [[ "$positional_index" == "0" ]]; then
                      vars=(${(f)"$(configen ${config_args[@]} completion-data variables --mode del 2>/dev/null)"})
                      _describe 'variables' vars
                      return
                    fi
                    ;;
                esac
              fi

              case "$cmd" in
        #{case_entries}      esac
              ;;
          esac
        }

        compdef _configen_completion configen
      ZSH
    end

    def build_fish_completion_script
      commands = completion_command_names
      global_options = completion_global_options
      command_options = completion_command_options
      command_entries = commands.map do |command_name|
        description = self.class.all_commands.fetch(command_name).description
        "complete -c configen -n \"__fish_use_subcommand\" -a \"#{command_name}\" -d #{single_quoted(description)}"
      end.join("\n")
      option_entries = commands.map do |command_name|
        options = (command_options.fetch(command_name, []) + global_options).uniq
        options.map do |option|
          fish_option_completion(command_name, option)
        end.join("\n")
      end.join("\n")

      <<~FISH
        function __fish_configen_config_value
          set -l tokens (commandline -opc)
          set -l value
          for i in (seq (count $tokens))
            set -l token $tokens[$i]
            switch $token
              case -c --config
                set -l j (math "$i + 1")
                if test $j -le (count $tokens)
                  set value $tokens[$j]
                end
              case '--config=*'
                set value (string replace -r '^--config=' '' -- $token)
            end
          end
          echo $value
        end

        function __fish_configen_themes
          set -l cfg (__fish_configen_config_value)
          if test -n "$cfg"
            configen --config "$cfg" completion-data themes 2>/dev/null
          else
            configen completion-data themes 2>/dev/null
          end
        end

        function __fish_configen_variables
          set -l mode $argv[1]
          set -l cfg (__fish_configen_config_value)
          if test -n "$cfg"
            configen --config "$cfg" completion-data variables --mode "$mode" 2>/dev/null
          else
            configen completion-data variables --mode "$mode" 2>/dev/null
          end
        end

        complete -c configen -f
        #{command_entries}

        # Global options
        complete -c configen -s c -l config -r

        # Command options
        #{option_entries}

        # Dynamic theme names
        complete -c configen -n "__fish_seen_subcommand_from theme" -a "(__fish_configen_themes)"

        # Dynamic variable paths
        complete -c configen -n "__fish_seen_subcommand_from get" -a "(__fish_configen_variables get)"
        complete -c configen -n "__fish_seen_subcommand_from set" -a "(__fish_configen_variables set)"
        complete -c configen -n "__fish_seen_subcommand_from del" -a "(__fish_configen_variables del)"

        # completion command shells
        complete -c configen -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
      FISH
    end

    def fish_option_completion(command_name, option)
      if option.start_with?("-") && option.length == 2
        return "complete -c configen -n \"__fish_seen_subcommand_from #{command_name}\" -s #{option.delete_prefix("-")}"
      end

      if option.start_with?("--")
        "complete -c configen -n \"__fish_seen_subcommand_from #{command_name}\" -l #{option.delete_prefix("--")}"
      else
        "complete -c configen -n \"__fish_seen_subcommand_from #{command_name}\" -a #{single_quoted(option)}"
      end
    end
  end
end
