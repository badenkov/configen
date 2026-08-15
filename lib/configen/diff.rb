# frozen_string_literal: true

# Minimal unified diff, no external dependencies.
#
# Myers greedy algorithm with a bounded edit distance: for a file whose content
# changed beyond `MAX_EDIT_DISTANCE` differing lines, a line-by-line diff carries
# no information anyway, so the whole body is reported as replaced.
module Configen::Diff
  CONTEXT = 3
  MAX_EDIT_DISTANCE = 1000
  BINARY_MARKER = "Binary files differ"

  module_function

  # Returns the unified diff body (already line-terminated) or an empty string
  # when both sides are identical.
  def unified(old_content, new_content, old_label:, new_label:)
    return "" if old_content == new_content
    return "--- #{old_label}\n+++ #{new_label}\n#{BINARY_MARKER}\n" if binary?(old_content) || binary?(new_content)

    hunks = hunks(split_lines(old_content), split_lines(new_content))
    return "" if hunks.empty?

    "--- #{old_label}\n+++ #{new_label}\n#{hunks.join}"
  end

  def binary?(content)
    content.include?("\0") || !content.dup.force_encoding(Encoding::UTF_8).valid_encoding?
  end

  def split_lines(content)
    content.lines.map(&:chomp)
  end

  def hunks(old_lines, new_lines)
    ops = edit_script(old_lines, new_lines)
    positions = line_positions(ops)
    group_hunks(ops).map { |range| render_hunk(ops[range], positions[range.first]) }
  end

  # For every op index, the 1-based line numbers it starts at on each side.
  def line_positions(ops)
    old_line = 1
    new_line = 1
    ops.map do |kind, _|
      position = [old_line, new_line]
      old_line += 1 unless kind == :add
      new_line += 1 unless kind == :del
      position
    end
  end

  # [[:eq | :del | :add, line], ...]
  def edit_script(old_lines, new_lines)
    head = common_prefix_size(old_lines, new_lines)
    tail = common_suffix_size(old_lines, new_lines, head)
    core_old = old_lines[head...(old_lines.size - tail)]
    core_new = new_lines[head...(new_lines.size - tail)]

    core = myers(core_old, core_new) || replace_wholesale(core_old, core_new)

    old_lines[0, head].map { |line| [:eq, line] } +
      core +
      old_lines[(old_lines.size - tail)..].map { |line| [:eq, line] }
  end

  def common_prefix_size(old_lines, new_lines)
    limit = [old_lines.size, new_lines.size].min
    (0...limit).each { |i| return i unless old_lines[i] == new_lines[i] }
    limit
  end

  def common_suffix_size(old_lines, new_lines, head)
    limit = [old_lines.size, new_lines.size].min - head
    (0...limit).each { |i| return i unless old_lines[-1 - i] == new_lines[-1 - i] }
    limit
  end

  def replace_wholesale(old_lines, new_lines)
    old_lines.map { |line| [:del, line] } + new_lines.map { |line| [:add, line] }
  end

  # Returns nil when the edit distance exceeds MAX_EDIT_DISTANCE.
  def myers(old_lines, new_lines)
    n = old_lines.size
    m = new_lines.size
    return new_lines.map { |line| [:add, line] } if n.zero?
    return old_lines.map { |line| [:del, line] } if m.zero?

    offset = MAX_EDIT_DISTANCE
    v = Array.new((2 * MAX_EDIT_DISTANCE) + 1, 0)
    trace = []

    (0..[n + m, MAX_EDIT_DISTANCE].min).each do |d|
      trace << v.dup
      (-d).step(d, 2) do |k|
        x = if k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])
              v[k + 1 + offset]
            else
              v[k - 1 + offset] + 1
            end
        y = x - k
        while x < n && y < m && old_lines[x] == new_lines[y]
          x += 1
          y += 1
        end
        v[k + offset] = x
        return backtrack(trace, old_lines, new_lines, offset) if x >= n && y >= m
      end
    end

    nil
  end

  def backtrack(trace, old_lines, new_lines, offset)
    x = old_lines.size
    y = new_lines.size
    ops = []

    trace.each_with_index.reverse_each do |(v, d)|
      k = x - y
      prev_k = if k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])
                 k + 1
               else
                 k - 1
               end
      prev_x = v[prev_k + offset]
      prev_y = prev_x - prev_k

      while x > prev_x && y > prev_y
        ops << [:eq, old_lines[x - 1]]
        x -= 1
        y -= 1
      end

      next if d.zero?

      if x == prev_x
        ops << [:add, new_lines[y - 1]]
        y -= 1
      else
        ops << [:del, old_lines[x - 1]]
        x -= 1
      end
    end

    ops.reverse
  end

  # Groups the edit script into hunks of changes surrounded by CONTEXT lines.
  def group_hunks(ops)
    changed_indexes = ops.each_index.reject { |i| ops[i][0] == :eq }
    return [] if changed_indexes.empty?

    ranges = []
    changed_indexes.each do |index|
      from = [index - CONTEXT, 0].max
      to = [index + CONTEXT, ops.size - 1].min
      if ranges.any? && from <= ranges.last.last + 1
        ranges[-1] = (ranges.last.first..to)
      else
        ranges << (from..to)
      end
    end

    ranges
  end

  SIGNS = { eq: " ", del: "-", add: "+" }.freeze

  def render_hunk(ops, (old_start, new_start))
    old_count = ops.count { |kind, _| kind != :add }
    new_count = ops.count { |kind, _| kind != :del }

    # An empty range is addressed by the line it follows, as in `diff -u`.
    old_start -= 1 if old_count.zero?
    new_start -= 1 if new_count.zero?

    header = "@@ -#{old_start},#{old_count} +#{new_start},#{new_count} @@\n"
    header + ops.map { |kind, line| "#{SIGNS.fetch(kind)}#{line}\n" }.join
  end
end
