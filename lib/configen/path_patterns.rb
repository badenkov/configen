# frozen_string_literal: true

# Single glob dialect used everywhere a path is matched against a pattern:
# template `ignore` (paths relative to the template target) and hook `changed`
# (paths relative to $HOME).
#
#   dir/**   dir/   whole subtree, any depth
#   **             every path
#   *.log          only at the root of the matched scope
#   **/*.log       at any depth
#   a/b.conf       exact path
module Configen::PathPatterns
  MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

  def self.match?(path, patterns)
    Array(patterns).any? { |pattern| matches?(path, pattern) }
  end

  def self.matches?(path, pattern)
    subtree = subtree_prefix(pattern)
    return true if subtree == ""
    return path == subtree || path.start_with?("#{subtree}/") if subtree

    File.fnmatch?(pattern, path, MATCH_FLAGS)
  end

  # Returns the directory prefix for subtree patterns (`dir/**`, `dir/`),
  # an empty string for the match-everything pattern (`**`), nil otherwise.
  def self.subtree_prefix(pattern)
    return pattern.delete_suffix("/**") if pattern.end_with?("/**")
    return pattern.delete_suffix("/") if pattern.end_with?("/")
    return "" if pattern == "**"

    nil
  end
  private_class_method :subtree_prefix
end
