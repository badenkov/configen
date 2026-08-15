# frozen_string_literal: true

require "test_helper"

class Configen::StrictOpenStructTest < Minitest::Test
  def build
    Configen::StrictOpenStruct.new(
      "font_size" => 13,
      "palette" => { "bg" => "#000", "fg" => "#fff" },
      "hosts" => [{ "name" => "alpha" }, { "name" => "beta" }]
    )
  end

  def test_reads_nested_values
    vars = build

    assert_equal 13, vars.font_size
    assert_equal "#000", vars.palette.bg
  end

  def test_hashes_inside_arrays_are_wrapped
    assert_equal %w[alpha beta], build.hosts.map(&:name)
  end

  def test_each_yields_pairs
    collected = build.palette.each.map { |name, value| "#{name}=#{value}" }

    assert_equal ["bg=#000", "fg=#fff"], collected
  end

  def test_to_h_returns_plain_ruby_structures
    assert_equal(
      { font_size: 13, palette: { bg: "#000", fg: "#fff" }, hosts: [{ name: "alpha" }, { name: "beta" }] },
      build.to_h
    )
  end

  def test_lookup_helpers
    vars = build

    assert_equal "#fff", vars.palette["fg"]
    assert vars.key?("palette")
    refute vars.key?("missing")
    assert_equal "#000", vars.dig("palette", "bg")
    refute_predicate vars, :empty?
  end

  def test_unknown_variable_raises_with_suggestion
    error = assert_raises(NameError) { build.font_sise }

    assert_includes error.message, "Undefined variable `font_sise`"
    assert_includes error.message, "Did you mean `font_size`?"
  end

  def test_unknown_key_lookup_is_strict_too
    assert_raises(NameError) { build.palette["nope"] }
  end

  def test_ruby_conversion_probes_do_not_look_like_variables
    assert_raises(NoMethodError) { build.to_ary }
  end

  def test_variables_named_like_collection_methods_are_still_readable
    vars = Configen::StrictOpenStruct.new("size" => 20, "count" => 3, "values" => "x", "map" => "y")

    assert_equal 20, vars.size
    assert_equal 3, vars.count
    assert_equal "x", vars.values
    assert_equal "y", vars.map
  end
end
