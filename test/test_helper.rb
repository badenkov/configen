# frozen_string_literal: true

require "configen"

require "minitest/autorun"
require 'minitest/hooks/default'
require "minitest/focus"

module Configen::TestHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  # def fixture(*path)
  #   Pathname.new(__FILE__).dirname.join("fixtures", *path)
  # end

  def file_fixture(*path)
    Pathname.new(__FILE__).dirname.join("fixtures", "files", *path)
  end
end

class Minitest::Test
  include Minitest::Hooks
  include Configen::TestHelpers
end

