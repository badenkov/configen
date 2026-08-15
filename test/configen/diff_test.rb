# frozen_string_literal: true

require "test_helper"

class Configen::DiffTest < Minitest::Test
  def unified(old_content, new_content)
    Configen::Diff.unified(old_content, new_content, old_label: "a/f", new_label: "b/f")
  end

  def test_identical_content_produces_no_diff
    assert_empty unified("a\nb\n", "a\nb\n")
  end

  def test_changed_line_is_reported_with_context
    diff = unified("a\nb\nc\nd\ne\nf\ng\nh\n", "a\nb\nc\nD\ne\nf\ng\nh\n")

    assert_equal <<~DIFF, diff
      --- a/f
      +++ b/f
      @@ -1,7 +1,7 @@
       a
       b
       c
      -d
      +D
       e
       f
       g
    DIFF
  end

  def test_distant_changes_produce_separate_hunks
    old_content = (1..20).map { |i| "line #{i}\n" }.join
    new_content = old_content.sub("line 2\n", "changed 2\n").sub("line 19\n", "changed 19\n")

    hunks = unified(old_content, new_content).scan(/^@@/).size
    assert_equal 2, hunks
  end

  def test_creation_and_deletion
    assert_includes unified("", "x\n"), "+x"
    assert_includes unified("x\n", ""), "-x"
  end

  def test_binary_content_is_not_diffed
    assert_includes unified("text\n", "bin\0ary\n"), Configen::Diff::BINARY_MARKER
  end

  def test_large_unrelated_rewrite_falls_back_to_wholesale_replacement
    old_content = (1..3000).map { |i| "old #{i}\n" }.join
    new_content = (1..3000).map { |i| "new #{i}\n" }.join

    diff = unified(old_content, new_content)
    assert_equal(3000, diff.lines.count { |line| line.start_with?("-old") })
    assert_equal(3000, diff.lines.count { |line| line.start_with?("+new") })
  end

  def test_line_numbers_follow_unified_format
    diff = unified("a\nb\nc\n", "a\nc\n")

    assert_includes diff, "@@ -1,3 +1,2 @@"
  end
end
