# frozen_string_literal: true

module Configen
  class Error < StandardError; end
end

require "zeitwerk"
require "tmpdir"
require "pathname"
require "erb"
require "ostruct"
require "thor"
require "json"
require "yaml"
require "fileutils"
require "digest"
require "tomlib"
# require "liquid"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "erb" => "ERB"
)
loader.setup
