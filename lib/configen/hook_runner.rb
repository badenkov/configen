# frozen_string_literal: true

require "open3"

class Configen::HookRunner
  MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH
  PlannedHook = Struct.new(:phase, :name, :run, keyword_init: true)

  def initialize(env: ENV, shell: nil, out: $stdout, err: $stderr)
    @env = env
    @shell = shell || "sh"
    @out = out
    @err = err
  end

  def run(phase:, hooks:, changed_paths:)
    result = {
      errors: []
    }

    hooks.each do |hook|
      next unless should_run_for_changes?(hook, changed_paths)
      next unless condition_allows?(hook)

      stdout, stderr, status = execute_hook(hook.run)
      next if status.success?

      result[:errors] << format_error(
        phase: phase,
        hook: hook,
        exit_code: status.exitstatus,
        stdout: stdout,
        stderr: stderr
      )
    rescue StandardError => e
      result[:errors] << "[#{phase}] #{hook.name}: exception while executing `#{hook.run}`: #{e.class}: #{e.message}"
    end

    result
  end

  def planned_hooks(phase:, hooks:, changed_paths:)
    hooks.filter_map do |hook|
      next unless should_run_for_changes?(hook, changed_paths)
      next unless condition_allows?(hook)

      PlannedHook.new(phase: phase, name: hook.name, run: hook.run)
    end
  end

  private

  def should_run_for_changes?(hook, changed_paths)
    return true if hook.changed.nil? || hook.changed.empty?

    hook.changed.any? do |pattern|
      changed_paths.any? { |path| path_matches_pattern?(path, pattern) }
    end
  end

  def path_matches_pattern?(path, pattern)
    if pattern.end_with?("/**")
      prefix = pattern.delete_suffix("/**")
      return path == prefix || path.start_with?("#{prefix}/")
    end

    File.fnmatch?(pattern, path, MATCH_FLAGS)
  end

  def condition_allows?(hook)
    return true if hook.if_command.nil? || hook.if_command.empty?

    _stdout, _stderr, status = Open3.capture3(@env, @shell, "-lc", hook.if_command)
    status.success?
  rescue StandardError
    false
  end

  def execute_hook(command)
    stdout_buffer = +""
    stderr_buffer = +""

    Open3.popen3(@env, @shell, "-lc", command) do |_stdin, stdout, stderr, wait_thr|
      out_thread = Thread.new do
        stdout.each_line do |line|
          @out.print(line)
          stdout_buffer << line
        end
      end
      err_thread = Thread.new do
        stderr.each_line do |line|
          @err.print(line)
          stderr_buffer << line
        end
      end

      out_thread.join
      err_thread.join
      [stdout_buffer, stderr_buffer, wait_thr.value]
    end
  end

  def format_error(phase:, hook:, exit_code:, stdout:, stderr:)
    output = compact_output(stderr)
    output = compact_output(stdout) if output.empty?
    suffix = output.empty? ? "" : " output: #{output}"

    "[#{phase}] #{hook.name}: command failed (exit #{exit_code}) `#{hook.run}`#{suffix}"
  end

  def compact_output(text)
    text.to_s.strip.gsub(/\s+/, " ")[0, 200]
  end
end
