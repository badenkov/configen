# frozen_string_literal: true

module Configen::CLICompletion
  private

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
            --theme)
              expect_value=1
              continue
              ;;
            --theme=*)
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

        if [[ "$cmd" == "theme" && "$cur" != -* ]]; then
          local themes
          themes="$(configen completion-data themes 2>/dev/null)"
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
                vars="$(configen completion-data variables 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$vars #{shell_words(global_options)}" -- "$cur") )
                return
              fi
              ;;
            set)
              if [[ "$positional_index" == "0" ]]; then
                local vars
                vars="$(configen completion-data variables 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$vars #{shell_words(global_options)}" -- "$cur") )
                return
              fi
              ;;
            del)
              if [[ "$positional_index" == "0" ]]; then
                local vars
                vars="$(configen completion-data variables 2>/dev/null)"
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
            --theme)
              expect_value=1
              continue
              ;;
            --theme=*)
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

            if [[ "$cmd" == "theme" && CURRENT -eq 3 ]]; then
              themes=(${(f)"$(configen completion-data themes 2>/dev/null)"})
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
                    vars=(${(f)"$(configen completion-data variables 2>/dev/null)"})
                    _describe 'variables' vars
                    return
                  fi
                  ;;
                set)
                  if [[ "$positional_index" == "0" ]]; then
                    vars=(${(f)"$(configen completion-data variables 2>/dev/null)"})
                    _describe 'variables' vars
                    return
                  fi
                  ;;
                del)
                  if [[ "$positional_index" == "0" ]]; then
                    vars=(${(f)"$(configen completion-data variables 2>/dev/null)"})
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
      function __fish_configen_themes
        configen completion-data themes 2>/dev/null
      end

      function __fish_configen_variables
        configen completion-data variables 2>/dev/null
      end

      complete -c configen -f
      #{command_entries}

      # Global options
      #{option_entries}

      # Dynamic theme names
      complete -c configen -n "__fish_seen_subcommand_from theme" -a "(__fish_configen_themes)"

      # Dynamic variable paths
      complete -c configen -n "__fish_seen_subcommand_from get" -a "(__fish_configen_variables)"
      complete -c configen -n "__fish_seen_subcommand_from set" -a "(__fish_configen_variables)"
      complete -c configen -n "__fish_seen_subcommand_from del" -a "(__fish_configen_variables)"

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
