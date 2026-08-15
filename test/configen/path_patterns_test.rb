# frozen_string_literal: true

require "test_helper"

class Configen::PathPatternsTest < Minitest::Test
  def match?(path, *patterns)
    Configen::PathPatterns.match?(path, patterns)
  end

  def test_subtree_patterns_are_equivalent_and_recursive
    ["plugins/", "plugins/**"].each do |pattern|
      assert match?("plugins/a.json", pattern)
      assert match?("plugins/deep/nested/a.json", pattern)
      assert match?("plugins", pattern)
      refute match?("plugins.json", pattern)
      refute match?("other/plugins/a.json", pattern)
    end
  end

  def test_star_matches_only_at_the_root_of_the_scope
    assert match?("app.log", "*.log")
    refute match?("logs/app.log", "*.log")
  end

  def test_double_star_prefix_matches_any_depth
    assert match?("app.log", "**/*.log")
    assert match?("logs/deep/app.log", "**/*.log")
  end

  def test_bare_double_star_matches_everything
    assert match?("a", "**")
    assert match?("a/b/c", "**")
  end

  def test_exact_path_and_dotfiles
    assert match?("plugins.json", "plugins.json")
    assert match?(".hidden", "*")
    refute match?("plugins.json", "plugins.yaml")
  end

  def test_empty_pattern_list_never_matches
    refute Configen::PathPatterns.match?("a", [])
    refute Configen::PathPatterns.match?("a", nil)
  end
end
