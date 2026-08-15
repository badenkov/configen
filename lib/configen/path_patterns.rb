# frozen_string_literal: true

module Configen::PathPatterns
  MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

  def self.match?(path, patterns)
    patterns.any? do |pattern|
      if pattern.end_with?("/")
        root = pattern.delete_suffix("/")
        path == root || path.start_with?(pattern)
      else
        File.fnmatch?(pattern, path, MATCH_FLAGS)
      end
    end
  end
end
