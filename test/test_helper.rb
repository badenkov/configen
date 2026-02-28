# frozen_string_literal: true

require "configen"
require "tmpdir"

require "minitest/autorun"
require "minitest/hooks/default"

class Minitest::Test
  include Minitest::Hooks
end
