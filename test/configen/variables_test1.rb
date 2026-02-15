# frozen_string_literal: true

require "test_helper"

class Configen::VariablesTest < Minitest::Test
  def setup
    @variables = Configen::Variables.new(
      files: {
        "file1" => "/home/dotfiles/variables/file1"
      },
      settings: {
        title: "Welcome"
      }
    )
    @theme = Configen::Variables.new(
      files: {
        "file2" => "/home/dotfiles/theme/file1"
      },
      settings: {
        colors: {
          red: "red"
        }
      }
    )
  end

  def test_merge
    result = @variables + @theme

    assert_equal "/home/dotfiles/variables/file1", result.files["file1"]
    assert_equal "/home/dotfiles/theme/file1", result.files["file2"]

    expected_settings = { title: "Welcome", colors: { red: "red" } }
    assert_equal expected_settings, result.settings
  end

  def test_fff
    vars = Configen::Variables.load_variables file_fixture("variables").to_s
    vars.s

    # binding.irb
  end
end
