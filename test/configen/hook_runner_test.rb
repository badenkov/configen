# frozen_string_literal: true

require "test_helper"
require "stringio"

class Configen::HookRunnerTest < Minitest::Test
  def test_run_streams_output_and_collects_failed_hook_error
    stdout = StringIO.new
    stderr = StringIO.new
    runner = Configen::HookRunner.new(shell: "sh", out: stdout, err: stderr)

    hooks = [
      Configen::Config::HookSpec.new(
        name: "ok",
        run: "echo hello; echo warn >&2",
        changed: nil,
        if_command: nil
      ),
      Configen::Config::HookSpec.new(
        name: "fail",
        run: "echo boom >&2; exit 7",
        changed: nil,
        if_command: nil
      )
    ]

    result = runner.run(phase: "after", hooks: hooks, changed_paths: [".config/kitty/kitty.conf"])

    assert_includes stdout.string, "hello\n"
    assert_includes stderr.string, "warn\n"
    assert_includes stderr.string, "boom\n"
    assert_equal 1, result[:errors].size
    assert_includes result[:errors][0], "[after] fail"
    assert_includes result[:errors][0], "exit 7"
  end
end
